module Main where

import Data.List (isPrefixOf)
import Network.URI
import System.Directory
import System.FilePath

import Distribution.Package

import Hackage.Security.Client.Repository
import Hackage.Security.TUF
import qualified Hackage.Security.Client                              as Client
import qualified Hackage.Security.Client.Repository.Local             as Local
import qualified Hackage.Security.Client.Repository.Remote            as Remote
import qualified Hackage.Security.Client.Repository.Remote.HTTP       as Remote.HTTP
import qualified Hackage.Security.Client.Repository.Remote.HttpClient as Remote.HttpClient
import qualified Hackage.Security.Client.Repository.Remote.Curl       as Remote.Curl

import ExampleClient.Options

main :: IO ()
main = do
    opts@GlobalOpts{..} <- getOptions
    case globalCommand of
      Bootstrap threshold -> bootstrap opts threshold
      Check               -> check     opts
      Get       pkgId     -> get       opts pkgId

{-------------------------------------------------------------------------------
  The commands are just thin wrappers around the hackage-security Client API
-------------------------------------------------------------------------------}

bootstrap :: GlobalOpts -> KeyThreshold -> IO ()
bootstrap opts threshold =
    withRepo opts $ \rep -> do
      Client.bootstrap rep (globalRootKeys opts) threshold
      putStrLn "OK"

check :: GlobalOpts -> IO ()
check opts =
    withRepo opts $ \rep ->
      print =<< Client.checkForUpdates rep (globalCheckExpiry opts)

get :: GlobalOpts -> PackageIdentifier -> IO ()
get opts pkgId =
    withRepo opts $ \rep ->
      Client.downloadPackage rep pkgId $ \tempPath ->
        copyFile tempPath localFile
  where
    localFile = "." </> pkgTarGz pkgId

{-------------------------------------------------------------------------------
  Common functionality
-------------------------------------------------------------------------------}

withRepo :: GlobalOpts -> (Repository -> IO a) -> IO a
withRepo GlobalOpts{..}
    | "http://" `isPrefixOf` globalRepo = withRemoteRepo
    | otherwise                         = withLocalRepo
  where
    withLocalRepo :: (Repository -> IO a) -> IO a
    withLocalRepo = Local.withRepository globalRepo globalCache logger

    withRemoteRepo :: (Repository -> IO a) -> IO a
    withRemoteRepo callback =
        withClient putStrLn $ \httpClient ->
          Remote.withRepository httpClient [baseURI] globalCache logger callback
      where
        baseURI :: URI
        baseURI = case parseURI globalRepo of
                    Nothing  -> error $ "Invalid URI: " ++ globalRepo
                    Just uri -> uri

    withClient :: (String -> IO ()) -> (Remote.HttpClient -> IO a) -> IO a
    withClient =
      case globalHttpClient of
        "HTTP"        -> Remote.HTTP.withClient
        "http-client" -> Remote.HttpClient.withClient
        "curl"        -> Remote.Curl.withClient
        _otherwise    -> error "unsupported HTTP client"

    logger :: LogMessage -> IO ()
    logger msg = putStrLn $ "# " ++ formatLogMessage msg
