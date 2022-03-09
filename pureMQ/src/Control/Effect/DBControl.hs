{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Effect.DBControl where

import           Control.Algebra
import           Data.Kind
import           Data.Set        (Set)
import           Data.Typeable
import           PureMQ.Database
import           PureMQ.Types


data DBControl (m :: Type -> Type) r where
  InitDB
    :: DBControl m Database

  AddStorage
    :: (Typeable k, Typeable v)
    => StorageName k v
    -> Set StorageType
    -> Database
    -> DBControl m ()

  RemoveStorage
    :: (Typeable k, Typeable v)
    => StorageName k v
    -> Database
    -> DBControl m ()

initDB
  :: Has DBControl sig m
  => m Database
initDB = send InitDB

addStorage
  :: ( Typeable k
     , Typeable v
     , Has DBControl sig m )
  => StorageName k v
  -> Set StorageType
  -> Database
  -> m ()
addStorage name storages db = send $ AddStorage name storages db

removeStorage
  :: ( Typeable k
     , Typeable v
     , Has DBControl sig m )
  => StorageName k v
  -> Database
  -> m ()
removeStorage name db = send $ RemoveStorage name db
