{-# LANGUAGE OverloadedStrings #-}

module Smos.Archive.OptParse.Types where

import Autodocodec
import Control.Monad.Logger
import Path
import qualified Smos.Report.Config as Report
import Smos.Report.Filter
import qualified Smos.Report.OptParse.Types as Report
import Smos.Report.Period
import Text.Read

data Arguments
  = Arguments
      !Command
      !(Report.FlagsWithConfigFile Flags)
  deriving (Show, Eq)

data Command
  = CommandFile !FilePath
  | CommandExport !ExportFlags
  deriving (Show, Eq)

data ExportFlags = ExportFlags
  { exportFlagExportDir :: FilePath,
    exportFlagFilter :: !(Maybe (Filter (Path Rel File))),
    exportFlagPeriod :: !(Maybe Period),
    exportFlagAlsoDeleteOriginals :: !(Maybe Bool)
  }
  deriving (Show, Eq)

data Flags = Flags
  { flagDirectoryFlags :: !Report.DirectoryFlags,
    flagLogLevel :: !(Maybe LogLevel)
  }
  deriving (Show, Eq)

data Environment = Environment
  { envDirectoryEnvironment :: !Report.DirectoryEnvironment,
    envLogLevel :: !(Maybe LogLevel)
  }
  deriving (Show, Eq)

data Configuration = Configuration
  { confDirectoryConfiguration :: !Report.DirectoryConfiguration,
    confLogLevel :: !(Maybe LogLevel)
  }
  deriving (Show, Eq)

instance HasCodec Configuration where
  codec =
    object "Configuration" $
      Configuration
        <$> Report.directoryConfigurationObjectCodec .= confDirectoryConfiguration
        <*> optionalFieldOrNullWith
          "log-level"
          (bimapCodec parseLogLevel renderLogLevel codec)
          "Minimal severity of log messages"
          .= confLogLevel

data Instructions = Instructions !Dispatch !Settings
  deriving (Show, Eq)

data Dispatch
  = DispatchFile !(Path Abs File)
  | DispatchExport !ExportSettings
  deriving (Show, Eq)

data ExportSettings = ExportSettings
  { exportSetExportDir :: !(Path Abs Dir),
    exportSetPeriod :: !Period,
    exportSetFilter :: !(Maybe (Filter (Path Rel File))),
    exportSetAlsoDeleteOriginals :: !Bool
  }
  deriving (Show, Eq)

data Settings = Settings
  { setDirectorySettings :: !Report.DirectoryConfig,
    setLogLevel :: !LogLevel
  }
  deriving (Show, Eq)

parseLogLevel :: String -> Either String LogLevel
parseLogLevel s = case readMaybe $ "Level" <> s of
  Nothing -> Left $ unwords ["Unknown log level: " <> show s]
  Just ll -> Right ll

renderLogLevel :: LogLevel -> String
renderLogLevel = drop 5 . show
