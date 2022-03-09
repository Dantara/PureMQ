module PureMQ.MVCC.Types where

import           Control.Concurrent
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Exception
import           Data.IntMap                  (IntMap)
import qualified Data.IntMap                  as Map
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet                  as Set
import           GHC.Generics
import           GHC.IORef
import           PureMQ.Types

newtype Key = Key { unKey :: Int }
  deriving (Show, Eq, Ord, Bounded, Num)

data MapMode
  = KeyValueM
  | CombinedM
  deriving (Eq, Ord, Show, Generic)

type family WithModeGlobal (m :: MapMode) where
  WithModeGlobal KeyValueM = ()
  WithModeGlobal CombinedM = QueueExtention

type family WithModeLocal (m :: MapMode) where
  WithModeLocal KeyValueM = ()
  WithModeLocal CombinedM = TChan ()

type KeyValueMap v = MvccMap KeyValueM v
type CombinedMap v = MvccMap CombinedM v

data MvccMap (m :: MapMode) v = MvccMap
  { primaryMap     :: IORef (IntMap v)
  , uncommitted    :: TVar (UncommittedTransactions m v)
  , committed      :: TVar (CommittedTransactions m v)
  , queueExtention :: WithModeGlobal m }
  deriving Generic

data QueueExtention = QueueExtention
  { nextKey  :: MVar Key
  , pullLock :: TChan () }
  deriving Generic

data UncommittedTransactions m v = UncommittedTransactions
  { nextKey      :: Int -- ^ Key for a new transaction
  , transactions :: IntMap (Transaction m v) }
  deriving Generic

data CommittedTransactions m v = CommittedTransactions
  { nextKey      :: Maybe Int -- ^ Key of oldest transaction
  , transactions :: IntMap (TransactionData m v) }
  deriving Generic

newtype Transaction m v = Transaction
  { unTransaction :: IORef (TransactionData m v) }
  deriving Generic

data TransactionData m v = TransactionData
  { modifyLog      :: ModifyLog v
  , deleteLog      :: DeleteLog
  , isolationLevel :: IsolationLevel
  , ranges         :: [(Maybe Int, Maybe Int)]
  , status         :: TransStatus
  , pullLock       :: WithModeLocal m }
  deriving Generic

newtype ModifyLog v = ModifyLog
  { unModifyLog :: IntMap v }
  deriving Generic

newtype DeleteLog = DeleteLog
  { unDeleteLog :: IntSet }
  deriving Generic

data MapError
  = NotSupportedOperationOnLevel IsolationLevel
  deriving (Eq, Ord, Show)

instance Exception MapError
