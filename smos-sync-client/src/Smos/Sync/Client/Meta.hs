{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Smos.Sync.Client.Meta where

import Data.Hashable
import qualified Data.Map as M
import Data.Map (Map)
import Data.Maybe (fromJust)

import qualified Data.Mergeful as Mergeful
import qualified Data.Mergeful.Timed as Mergeful

import Path

import Control.Monad.Reader

import Database.Persist.Sql as DB

import Smos.Client

import Smos.Sync.Client.Contents
import Smos.Sync.Client.DB
import Smos.Sync.Client.Env
import Smos.Sync.Client.MetaMap (MetaMap(..))
import qualified Smos.Sync.Client.MetaMap as MM
import Smos.Sync.Client.OptParse.Types

readClientMetadata :: MonadIO m => SqlPersistT m MetaMap
readClientMetadata = do
  cfs <- selectList [] []
  pure $
    fromJust $ -- Safe because of DB constraints
    MM.fromList $
    map
      (\(Entity _ ClientFile {..}) ->
         ( clientFilePath
         , SyncFileMeta
             { syncFileMetaUUID = clientFileUuid
             , syncFileMetaHash = clientFileHash
             , syncFileMetaTime = clientFileTime
             }))
      cfs

writeClientMetadata ::
     forall m. MonadIO m
  => MetaMap
  -> SqlPersistT m ()
writeClientMetadata mm = do
  let m = metaMapFiles mm
  deleteWhere [ClientFilePath /<-. M.keys m]
  void $ M.traverseWithKey go m
  where
    go :: Path Rel File -> SyncFileMeta -> SqlPersistT m ()
    go path SyncFileMeta {..} =
      void $
      upsertBy
        (UniquePath path)
        (ClientFile
           { clientFileUuid = syncFileMetaUUID
           , clientFilePath = path
           , clientFileHash = syncFileMetaHash
           , clientFileTime = syncFileMetaTime
           })
        [ClientFileHash =. syncFileMetaHash, ClientFileTime =. syncFileMetaTime]

-- | We only check the synced items, because it should be the case that
-- they're the only ones that are not empty.
makeClientMetaData :: IgnoreFiles -> ClientStore -> MetaMap
makeClientMetaData igf ClientStore {..} =
  let Mergeful.ClientStore {..} = clientStoreItems
   in if not
           (null clientStoreAddedItems &&
            null clientStoreDeletedItems && null clientStoreSyncedButChangedItems)
        then error "Should not happen: make meta"
        else let go :: MetaMap -> FileUUID -> Mergeful.Timed SyncFile -> MetaMap
                 go m u Mergeful.Timed {..} =
                   let SyncFile {..} = timedValue
                       goOn =
                         fromJust $ -- Safe because of validity constraints
                         MM.insert
                           syncFilePath
                           SyncFileMeta
                             { syncFileMetaUUID = u
                             , syncFileMetaTime = timedTime
                             , syncFileMetaHash = hash syncFileContents
                             }
                           m
                    in case igf of
                         IgnoreNothing -> goOn
                         IgnoreHiddenFiles ->
                           if isHidden syncFilePath
                             then m
                             else goOn
              in M.foldlWithKey go MM.empty clientStoreSyncedItems
