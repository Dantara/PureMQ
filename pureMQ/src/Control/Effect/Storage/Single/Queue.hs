module Control.Effect.Storage.Single.Queue where

import           Control.Algebra
import           Data.Kind

data QueueStorage v (m :: Type -> Type) r where
  Push        :: v -> QueueStorage v m ()
  Pull        :: QueueStorage v m v
  PullIfExist :: QueueStorage v m (Maybe v)
  Peek        :: QueueStorage v m v
  PeekIfExist :: QueueStorage v m (Maybe v)

push
  :: forall v m sig
  .  Has (QueueStorage v) sig m
  => v -> m ()
push v = send $ Push v

pull
  :: forall v m sig
  .  Has (QueueStorage v) sig m
  => m v
pull = send $ Pull @v

pullIfExist
  :: forall v m sig
  .  Has (QueueStorage v) sig m
  => m (Maybe v)
pullIfExist = send PullIfExist

peek
  :: forall v m sig
  .  Has (QueueStorage v) sig m
  => m v
peek = send Peek

peekIfExist
  :: forall v m sig
  .  Has (QueueStorage v) sig m
  => m (Maybe v)
peekIfExist = send PeekIfExist
