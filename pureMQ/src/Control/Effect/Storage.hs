module Control.Effect.Storage
  ( module S
  , CombinedStorage
  ) where

import           Control.Algebra
import           Control.Effect.Storage.KeyValue as S
import           Control.Effect.Storage.Queue    as S

type CombinedStorage m r = (KeyValueStorage :+: QueueStorage) m r
