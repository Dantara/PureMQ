module Control.Effect.Storage
  ( module S
  , CombinedStorage
  ) where

import           Control.Algebra
import           Control.Effect.Storage.Common   as S
import           Control.Effect.Storage.KeyValue as S
import           Control.Effect.Storage.Queue    as S

type CombinedStorage k v m r = (KeyValueStorage k v :+: QueueStorage v) m r
