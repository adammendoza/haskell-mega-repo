module Futurice.App.Proxy.Config (
    Config(..),
    getConfig,
    ) where

import Futurice.Prelude
import Prelude          ()

import Data.ByteString    (ByteString)
import Futurice.EnvConfig

data Config = Config
    { cfgPort             :: !Int
    , cfgFutuhoursBaseurl :: !String
    , cfgBasicAuthUser    :: !ByteString
    , cfgBasicAuthPass    :: !ByteString
    }

-- | TODO: parse
getConfig :: IO Config
getConfig = Config
    <$> parseDefaultPort
    <*> parseEnvVar "FUTUHOURS_BASEURL"
    <*> parseEnvVar "PROXYAPP_USER"
    <*> parseEnvVar "PROXYAPP_PASS"
