{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE MagicHash #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Monad.STM
-- Copyright   :  (c) The University of Glasgow 2004
-- License     :  BSD-style (see the file libraries/base/LICENSE)
-- 
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  non-portable (requires STM)
--
-- Software Transactional Memory: a modular composable concurrency
-- abstraction.  See
--
--  * /Composable memory transactions/, by Tim Harris, Simon Marlow, Simon
--    Peyton Jones, and Maurice Herlihy, in /ACM Conference on Principles
--    and Practice of Parallel Programming/ 2005.
--    <http://research.microsoft.com/Users/simonpj/papers/stm/index.htm>
--
-- This module only defines the 'STM' monad; you probably want to 
-- import "Control.Concurrent.STM" (which exports "Control.Monad.STM").
-----------------------------------------------------------------------------

module Control.Monad.STM (
  	STM,
	atomically,
#ifdef __GLASGOW_HASKELL__
        always,
        alwaysSucceeds,
	retry,
	orElse,
	check,
#endif
        throwSTM,
        catchSTM
  ) where

#ifdef __GLASGOW_HASKELL__
#if ! (MIN_VERSION_base(4,3,0))
import GHC.Conc hiding (catchSTM)
import Control.Monad    ( MonadPlus(..) )
import GHC.Exts (raiseIO#, catchSTM#)
import Control.Exception
#else
import GHC.Conc
#endif
#else
import Control.Sequential.STM
#endif

#ifdef __GLASGOW_HASKELL__
#if ! (MIN_VERSION_base(4,3,0))
instance MonadPlus STM where
  mzero = retry
  mplus = orElse
#endif

check :: Bool -> STM a
check b = if b then return undefined else retry
#endif

#if ! (MIN_VERSION_base(4,3,0))
-- |Exception handling within STM actions.
catchSTM :: Exception e => STM a -> (e -> STM a) -> STM a
catchSTM (STM m) handler = STM $ catchSTM# m handler'
    where
      handler' e = case fromException e of
                     Just e' -> case handler e' of STM m' -> m'
                     Nothing -> raiseIO# e

-- | A variant of 'throw' that can only be used within the 'STM' monad.
--
-- Throwing an exception in @STM@ aborts the transaction and propagates the
-- exception.
--
-- Although 'throwSTM' has a type that is an instance of the type of 'throw', the
-- two functions are subtly different:
--
-- > throw e    `seq` x  ===> throw e
-- > throwSTM e `seq` x  ===> x
--
-- The first example will cause the exception @e@ to be raised,
-- whereas the second one won\'t.  In fact, 'throwSTM' will only cause
-- an exception to be raised when it is used within the 'STM' monad.
-- The 'throwSTM' variant should be used in preference to 'throw' to
-- raise an exception within the 'STM' monad because it guarantees
-- ordering with respect to other 'STM' operations, whereas 'throw'
-- does not.
throwSTM :: Exception e => e -> STM a
throwSTM e = STM $ raiseIO# (toException e)
#endif
