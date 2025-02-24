{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Smos.Sync.Client.DB
  ( module Smos.Sync.Client.DB,
    module Database.Persist,
    module Database.Persist.Sql,
  )
where

import Data.Mergeful.Timed
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics (Generic)
import Path
import Smos.API

share
  [mkPersist sqlSettings, mkMigrate "syncClientAutoMigration"]
  [persistLowerCase|

ClientFile
    path (Path Rel File)
    sha256 SHA256
    time ServerTime

    UniquePath path

    deriving Show
    deriving Eq
    deriving Generic
|]
