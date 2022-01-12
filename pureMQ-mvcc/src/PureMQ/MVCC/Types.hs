module PureMQ.MVCC.Types where

import           Control.Concurrent
import           Control.Concurrent.STM.TVar
import           Data.IntMap                 (IntMap)
import qualified Data.IntMap                 as Map
import           Data.IntSet                 (IntSet)
import qualified Data.IntSet                 as Set
import           Data.Sequence               (Seq (..))
import qualified Data.Sequence               as Seq
import           GHC.Generics
import           GHC.IORef
import           PureMQ.Types

newtype Key = Key { unKey :: Int }
  deriving (Show, Eq, Ord, Bounded, Num)

data MapMode
  = KeyValue
  | Combined
  deriving (Eq, Ord, Show, Generic)

type family WithMode (m :: MapMode) where
  WithMode KeyValue = ()
  WithMode Combined = QueueExtention

type KeyValueMap v = MvccMap KeyValue v
type CombinedMap v = MvccMap Combined v

data MvccMap (m :: MapMode) v = MvccMap
  { primaryMap     :: IORef (IntMap v)
  , uncommitted    :: TVar (UncommittedTransactions v)
  , committed      :: TVar (CommittedTransactions v)
  , queueExtention :: WithMode m }
  deriving Generic

data QueueExtention = QueueExtention
  { nextKey  :: MVar Key
  , pullLock :: Chan () }
  deriving Generic

data UncommittedTransactions v = UncommittedTransactions
  { nextKey      :: Int
  , transactions :: IntMap (Transaction v) }
  deriving Generic

data CommittedTransactions v = CommittedTransactions
  { nextKey      :: Maybe Int
  , transactions :: IntMap (TransactionData v) }
  deriving Generic

newtype Transaction v = Transaction
  { unTransaction :: IORef (TransactionData v) }
  deriving Generic

data TransactionData v = TransactionData
  { modifyLog      :: ModifyLog v
  , deleteLog      :: DeleteLog
  , isolationLevel :: IsolationLevel
  , ranges         :: [(Maybe Int, Maybe Int)]
  , status         :: TransStatus }
  deriving Generic

newtype ModifyLog v = ModifyLog
  { unModifyLog :: IntMap v }
  deriving Generic

newtype DeleteLog = DeleteLog
  { unDeleteLog :: IntSet }
  deriving Generic
