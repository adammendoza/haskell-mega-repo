{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}
module Main (main) where

import PlanMill.Internal.Prelude

import Control.Arrow        ((&&&))
import Control.Monad.Http   (HttpT, evalHttpT)
import Control.Monad.Logger (LogLevel (..), LogSource, LoggingT, filterLogger)
import Control.Monad.Reader (ReaderT (..))
import Data.Maybe           (isJust)
import Data.Time.TH         (mkUTCTime)
import Data.Yaml            (decodeFileEither)
import Generics.SOP         (All)
import System.Environment   (getArgs, lookupEnv)
import System.IO            (hPutStrLn, stderr)

import qualified Data.HashMap.Strict as HM

import Control.Monad.PlanMill
import PlanMill

import Caching     (CachingT (..))
import MonadPretty (MonadPretty (..))

data Dump = Dump
    { dumpProjects    :: HM.HashMap ProjectId Project
    , dumpTasks       :: HM.HashMap TaskId Task
    , dumpAssignments :: HM.HashMap AssignmentId Assignment
    , dumpTeams       :: HM.HashMap TeamId Team
    , dumpUsers       :: HM.HashMap UserId User
    }
    deriving Show

directUsersTeams :: ( MonadPlanMill m, MonadCatch m, Applicative m
                    , MonadPlanMillC m Teams
                    , MonadPlanMillC m Users
                    )
                 => m (Users, Teams)
directUsersTeams = (,) <$> u <*> t
  where
    u = planmillAction users `catch` onPlanmillError (pure mempty)
    t = planmillAction teams `catch` onPlanmillError (pure mempty)

getDump :: ( MonadPlanMill m, MonadIO m, MonadCatch m, Applicative m
           , MonadPlanMillC m Me
           , MonadPlanMillC m User
           , MonadPlanMillC m Projects
           , MonadPlanMillC m Tasks
           , MonadPlanMillC m Assignments
           , MonadPlanMillC m Teams
           , MonadPlanMillC m Users
           )
        => m Dump
getDump = do
    me' <- planmillAction me
    liftIO $ putPretty me'
    me'' <- planmillAction $ user (me' ^. identifier)
    liftIO $ putPretty me''
    ps <- planmillAction projects
    ts <- fold <$> traverse (planmillAction . projectTasks . view identifier) (toList ps)
    as <- fold <$> traverse (planmillAction . projectAssignments . view identifier) (toList ps)
    (us, t) <- directUsersTeams
    pure Dump
        { dumpProjects    = toLookupHM ps
        , dumpTasks       = toLookupHM ts
        , dumpAssignments = toLookupHM as
        , dumpTeams       = toLookupHM t
        , dumpUsers       = toLookupHM us
        }

onPlanmillError :: a -> PlanMillError -> a
onPlanmillError = const

toLookupHM :: (Foldable f, HasIdentifier a b) => f a -> HM.HashMap (Identifier b) a
toLookupHM = HM.fromList . map (view identifier &&& id) . toList

printDumpStats :: Dump -> IO ()
printDumpStats (Dump ps ts as t us) = do
    putStrLn $ "projects:    " <> show (HM.size ps)
    putStrLn $ "tasks:       " <> show (HM.size ts)
    putStrLn $ "assignments: " <> show (HM.size as)
    putStrLn $ "teams:       " <> show (HM.size t)
    putStrLn $ "users:       " <> show (HM.size us)

-------------------------------------------------------------------------------
-- My projects
-------------------------------------------------------------------------------

myProjects :: ( MonadPlanMill m, MonadIO m, MonadCatch m, Applicative m
              , MonadPlanMillC m Me
              , MonadPlanMillC m ReportableAssignments
              )
           => m ()
myProjects = do
    me' <- planmillAction me
    putPretty me'
    as <- planmillAction $ reportableAssignments (me' ^. identifier)
    putPretty as

-------------------------------------------------------------------------------
-- Timereports
-------------------------------------------------------------------------------

myTimereports
    :: ( MonadPlanMill m, MonadIO m, MonadThrow m
       , All (MonadPlanMillC m) '[Me, User, Team, Timereports]
       )
    => m ()
myTimereports = do
    me' <- planmillAction me
    putPretty me'
    let ident = Ident 17549
    u <- planmillAction $ user ident
    putPretty u
    t <- traverse (planmillAction . team) (uTeam u)
    putPretty t
    interval <- mkInterval
        (utctDay $(mkUTCTime "2016-03-01T00:00:00.000Z"))
        (utctDay $(mkUTCTime "2016-05-01T00:00:00.000Z"))
    let interval' = ResultInterval IntervalStart $ intervalDayToIntervalUTC interval
    trs <- planmillAction $ timereportsFromIntervalFor interval' ident
    putPretty trs

-------------------------------------------------------------------------------
-- Capacity calendar
-------------------------------------------------------------------------------

capacityCalendar
    :: ( MonadPlanMill m, MonadIO m, MonadThrow m
       , All (MonadPlanMillC m) '[Me, UserCapacities]
       )
    => m ()
capacityCalendar = do
    me' <- planmillAction me
    putPretty me'
    interval <- mkInterval
        (utctDay $(mkUTCTime "2016-01-01T00:00:00.000Z"))
        (utctDay $(mkUTCTime "2016-02-01T00:00:00.000Z"))
    cc <- planmillAction $ userCapacity interval $ Ident 17557
    putPretty cc

-------------------------------------------------------------------------------
-- Enumerations
-------------------------------------------------------------------------------

enumerationsCommand
    :: ( MonadPlanMill m, MonadIO m, MonadThrow m
       , All (MonadPlanMillC m) '[Meta, Me, User]
       , ForallFSymbol (MonadPlanMillC m) EnumDesc
       )
    => m ()
enumerationsCommand = do
    me' <- planmillAction me
    putPretty me'
    u <- planmillAction $ user $ me' ^. identifier
    putPretty u
    contractType <- enumerationValue (uContractType u) "Unknown contract type"
    putPretty contractType

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

newtype Cfg' = Cfg' { getCfg' :: Cfg }

instance FromJSON Cfg' where
    parseJSON = fmap Cfg' . parseJSON'
      where
        parseJSON' = withObject "Cfg" $ \obj ->
            Cfg <$> obj .: "userid"
                <*> (ApiKey . fromString <$> obj .: "apikey")
                <*> obj .: "baseurl"

-------------------------------------------------------------------------------
-- Cli interface
-------------------------------------------------------------------------------

main'' :: Cfg -> String -> IO ()
main'' cfg script = do
    debug <- isJust <$> lookupEnv "DEBUG"
    action & id
        . evalHttpT
        . runStderrLoggingT
        . filterLogger (logPredicate debug)
        . flip runReaderT cfg
        . runCachingT
  where
    logPredicate :: Bool -> LogSource -> LogLevel -> Bool
    logPredicate debug _ level = debug || level > LevelDebug

    action :: CachingT (ReaderT Cfg (LoggingT (HttpT IO))) ()
    action = case script of
        "dump" -> do dump <- getDump
                     liftIO $ printDumpStats dump
        "myprojects" -> myProjects
        "capacitycalendar" -> capacityCalendar
        "timereports" -> myTimereports
        "enumerations" -> enumerationsCommand
        _      -> liftIO $ putStrLn $ "Unknown script: " ++ script

main' :: FilePath -> String -> IO ()
main' cfgPath script = do
    ecfg <- fmap getCfg' <$> decodeFileEither cfgPath
    case ecfg of
        Left err -> hPutStrLn stderr $ show err
        Right cfg -> main'' cfg script

main :: IO ()
main = do
    args <- getArgs
    case args of
        [cfgfile]         -> main' cfgfile "dump"
        [cfgfile, script] -> main' cfgfile script
        _                 ->
            hPutStrLn stderr "Usage: ./planmill-client cfgfile [script]"
