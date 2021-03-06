{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE NoImplicitPrelude  #-}
module Futurice.App.MegaRepoTool (defaultMain) where

import Futurice.Prelude

import qualified Turtle
import qualified Options.Applicative as O

import Futurice.App.MegaRepoTool.Command.ListSnapshotDependencies
import Futurice.App.MegaRepoTool.Command.BuildDocker
import Futurice.App.MegaRepoTool.Scripts

data Cmd
    = ListSnapshotDependencies 
    | BuildDocker
    | Script (Turtle.Shell Text)

listSnapshotDependenciesOptions :: O.Parser Cmd
listSnapshotDependenciesOptions = pure ListSnapshotDependencies

buildDockerOptions :: O.Parser Cmd
buildDockerOptions = pure BuildDocker

packdepsOptions :: O.Parser Cmd
packdepsOptions = pure $ Script packdepsScript

dotOptions :: O.Parser Cmd
dotOptions = pure $ Script dotScript

statsOptions :: O.Parser Cmd
statsOptions =  pure $ Script statsScript

optsParser :: O.Parser Cmd
optsParser = O.subparser $ mconcat
    [ cmdParser "build-docker" buildDockerOptions "Build docker images"
    , cmdParser "list-snapshot-dependencies" listSnapshotDependenciesOptions "List snapshot dependencies (like stack list-dependencies)"
    , cmdParser "packdeps" packdepsOptions "Run packdeps, i.e. check that dependency bounds allow newest versions"
    , cmdParser "dot" dotOptions "Update dependency graph image"
    , cmdParser "stats" statsOptions "Display some rough stats"
    ]
  where
    cmdParser :: String -> O.Parser Cmd -> String -> O.Mod O.CommandFields Cmd
    cmdParser cmd parser desc =
         O.command cmd $ O.info (O.helper <*> parser) $ O.progDesc desc

main' :: Cmd -> IO ()
main' ListSnapshotDependencies = listSnapshotDependencies
main' BuildDocker = buildDocker
main' (Script cmd) = Turtle.stdout cmd

defaultMain :: IO ()
defaultMain =
    O.execParser opts >>= main'
  where
    opts = O.info (O.helper <*> optsParser) $ mconcat
        [ O.fullDesc
        , O.progDesc "Futurice haskell-mega-repo tool"
        , O.header "mega-repo-tool"
        ]
