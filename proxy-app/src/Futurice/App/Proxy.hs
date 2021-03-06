{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
module Futurice.App.Proxy (defaultMain) where

import Futurice.Prelude
import Prelude          ()

import Data.Csv.Futurice
import Futurice.Colour
import Network.Wai
import Servant
import Servant.Cache.Class (DynMapCache)
import Servant.Client
import Servant.Proxy
import System.IO           (hPutStrLn, stderr)

import qualified Network.Wai.Handler.Warp      as Warp
import qualified Servant.Cache.Internal.DynMap as DynMap

import Servant.Futurice

import Futurice.App.FutuHours.Types (MissingHour)

import Network.HTTP.Client     (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.Wai.Middleware.HttpAuth (basicAuth)

import Futurice.App.Proxy.Config

data Ctx = Ctx
    { ctxManager          :: !Manager
    , ctxFutuhoursBaseurl :: !BaseUrl
    }

makeProxy
    :: forall api.
      ( Proxyable api
      , S (ProxyNamespace api :> ProxiedAPI api) ~ Server (ProxyNamespace api :> ProxiedAPI api)
      , (Manager -> BaseUrl -> C (ProxiedAPI api)) ~ Client (ProxiedAPI api)
      , HasClient (ProxiedAPI api)
      )
    => Proxy api -> Ctx -> Server (ProxyNamespace api :> ProxiedAPI api)
makeProxy _ ctx = proxy' p (client p manager baseurl)
  where
    baseurl = ctxFutuhoursBaseurl ctx  -- TODO: make a class with Ctx -> BaseUrl
    manager = ctxManager ctx
    p :: Proxy (ProxiedAPI api)
    p = Proxy

data API = Futuhours

type FutuhoursAPI = "reports" :> "missinghours-list" :> Get '[FutuCSV, JSON] [MissingHour]
instance Proxyable 'Futuhours where
    type ProxyNamespace 'Futuhours = "futuhours"
    type ProxiedAPI 'Futuhours = FutuhoursAPI

type ProxyAPI = Get '[JSON] Text
    :<|> Proxied 'Futuhours

type ProxyAPI' = FuturiceAPI ProxyAPI ('FutuAccent 'AF3 'AC3)

proxyAPI :: Proxy ProxyAPI
proxyAPI = Proxy

proxyAPI' :: Proxy ProxyAPI'
proxyAPI' = Proxy

-------------------------------------------------------------------------------
-- WAI/startup
-------------------------------------------------------------------------------

server :: Ctx -> Server ProxyAPI
server ctx = pure "P-R-O-X-Y" :<|> makeProxy (Proxy :: Proxy 'Futuhours) ctx

-- | Server with docs and cache and status
server' :: DynMapCache -> Ctx -> Server ProxyAPI'
server' cache ctx = futuriceApiServer cache proxyAPI (server ctx)

-- | Wai application
app :: DynMapCache -> Ctx -> Application
app cache ctx = serve proxyAPI' (server' cache ctx)

defaultMain :: IO ()
defaultMain = do
    hPutStrLn stderr "Hello, proxy-app is alive"
    Config{..} <- getConfig
    mgr <- newManager tlsManagerSettings
    cache <- DynMap.newIO
    futuhoursBaseurl <- parseBaseUrl cfgFutuhoursBaseurl
    let ctx = Ctx mgr futuhoursBaseurl
    let checkCreds u p = pure (u == cfgBasicAuthUser && p == cfgBasicAuthPass)
    let app' = basicAuth checkCreds "P-R-O-X-Y" $ app cache ctx
    hPutStrLn stderr "Starting web server"
    Warp.run cfgPort app'
