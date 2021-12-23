module PureMQ.MVCC.Types where

import           Control.Concurrent
import           Control.Concurrent.Chan.Unagi
import           Data.IntMap                   (IntMap)
import qualified Data.IntMap                   as Map
import           Data.IntSet                   (IntSet)
import qualified Data.IntSet                   as Set
import           Data.Sequence                 (Seq (..))
import qualified Data.Sequence                 as Seq
import           GHC.Generics
import           GHC.IORef
import           PureMQ.Types

newtype Key = Key { unKey :: Int }
  deriving (Show, Eq, Ord, Bounded, Num)

data MapMode
  = KeyVal
  | Combined
  deriving (Eq, Ord, Show, Generic)

type family WithMode (m :: MapMode) where
  WithMode KeyVal = ()
  WithMode Combined = MVar Int

type KeyValMap v   = MvccMap KeyVal v
type CombinedMap v = MvccMap Combined v

data MvccMap (m :: MapMode) v = MvccMap
  { primaryMap        :: IORef (IntMap v)
  , transactionsQueue :: MVar (Seq (Transaction v))
  , nextKey           :: WithMode m }
  deriving Generic

newtype Transaction v = Transaction
  { unTrasaction :: IORef (TransactionData v) }
  deriving Generic

data TransactionData v = TransactionData
  { modifyLog :: ModifyLog v
  , deleteLog :: DeleteLog
  , status    :: TransStatus }
  deriving Generic

newtype ModifyLog v = ModifyLog
  { unModifyLog :: IntMap v }
  deriving Generic

newtype DeleteLog = DeleteLog
  { unDeleteLog :: IntSet }
  deriving Generic
