{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Smos.Report.Waiting where

import Conduit
import Data.Aeson
import qualified Data.Conduit.Combinators as C
import Data.List
import Data.Time
import Data.Validity
import Data.Validity.Time ()
import GHC.Generics
import Path
import Smos.Data
import Smos.Report.Archive
import Smos.Report.Config
import Smos.Report.Filter
import Smos.Report.Streaming
import YamlParse.Applicative

newtype WaitingReport
  = WaitingReport
      { waitingReportEntries :: [WaitingEntry]
      }
  deriving (Show, Eq, Generic)

instance Validity WaitingReport where
  validate wr@WaitingReport {..} =
    mconcat
      [ genericValidate wr,
        declare "The waiting report entries are in order" $ sortOn waitingEntryTimestamp waitingReportEntries == waitingReportEntries
      ]

instance FromJSON WaitingReport

instance ToJSON WaitingReport

produceWaitingReport :: MonadIO m => Maybe EntryFilterRel -> HideArchive -> DirectoryConfig -> m WaitingReport
produceWaitingReport ef ha dc = produceReport ha dc (waitingReportConduit ef)

waitingReportConduit :: Monad m => Maybe EntryFilterRel -> ConduitT (Path Rel File, SmosFile) void m WaitingReport
waitingReportConduit ef =
  finishWaitingReport . WaitingReport
    <$> ( smosFileCursors
            .| smosFilter (maybe isWaitingFilter (FilterAnd isWaitingFilter) ef)
            .| smosCursorCurrents
            .| C.concatMap (uncurry makeWaitingEntry)
            .| sinkList
        )
  where
    isWaitingFilter :: EntryFilterRel
    isWaitingFilter = FilterSnd $ FilterWithinCursor $ FilterEntryTodoState $ FilterMaybe False $ FilterSub "WAITING"
    finishWaitingReport :: WaitingReport -> WaitingReport
    finishWaitingReport wr = wr {waitingReportEntries = sortOn waitingEntryTimestamp (waitingReportEntries wr)}

data WaitingEntry
  = WaitingEntry
      { waitingEntryHeader :: Header,
        waitingEntryTimestamp :: UTCTime,
        waitingEntryFilePath :: Path Rel File
      }
  deriving (Show, Eq, Generic)

instance Validity WaitingEntry

instance YamlSchema WaitingEntry where
  yamlSchema =
    objectParser "WaitingEntry" $
      WaitingEntry
        <$> requiredField "header" "The entry header"
        <*> requiredFieldWith "timestamp" "The timestamp at which this entry became WAITING" utcSchema
        <*> requiredField "path" "The path of the file that contained this waiting entry"

instance FromJSON WaitingEntry where
  parseJSON = viaYamlSchema

instance ToJSON WaitingEntry where
  toJSON WaitingEntry {..} =
    object
      [ "header" .= waitingEntryHeader,
        "timestamp" .= formatTime defaultTimeLocale utcFormat waitingEntryTimestamp,
        "path" .= waitingEntryFilePath
      ]

makeWaitingEntry :: Path Rel File -> Entry -> Maybe WaitingEntry
makeWaitingEntry rp Entry {..} = do
  time <-
    case unStateHistory entryStateHistory of
      [] -> Nothing
      x : _ -> Just $ stateHistoryEntryTimestamp x
  pure
    WaitingEntry
      { waitingEntryHeader = entryHeader,
        waitingEntryTimestamp = time,
        waitingEntryFilePath = rp
      }
