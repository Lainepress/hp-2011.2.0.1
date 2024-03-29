-- #hide
--------------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.OpenGL.GL.Tensor
-- Copyright   :  (c) Sven Panne 2002-2009
-- License     :  BSD-style (see the file libraries/OpenGL/LICENSE)
-- 
-- Maintainer  :  sven.panne@aedion.de
-- Stability   :  stable
-- Portability :  portable
--
-- This is a purely internal module for points, vectors and matrices.
--
--------------------------------------------------------------------------------

module Graphics.Rendering.OpenGL.GL.Tensor (
   Vertex1(..), Vertex2(..), Vertex3(..), Vertex4(..),
   Vector1(..), Vector2(..), Vector3(..), Vector4(..)
) where

import Control.Applicative ( Applicative(..) )
import Control.Monad ( ap )
import Data.Foldable ( Foldable(..) )
import Data.Ix ( Ix )
import Data.Traversable ( Traversable(..) )
import Data.Typeable (
   Typeable(..), mkTyCon, mkTyConApp, Typeable1(..), typeOfDefault )
import Foreign.Ptr ( castPtr )
import Foreign.Storable ( Storable(..) )
import Graphics.Rendering.OpenGL.GL.PeekPoke (
   poke1, poke2, poke3, poke4, peek1, peek2, peek3, peek4 )

--------------------------------------------------------------------------------

-- | A vertex with /y/=0, /z/=0 and /w/=1.
newtype Vertex1 a = Vertex1 a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vertex1 where
   fmap f (Vertex1 x) = Vertex1 (f x)

instance Applicative Vertex1 where
   pure a = Vertex1 a
   Vertex1 f <*> Vertex1 x = Vertex1 (f x)

instance Foldable Vertex1 where
   foldr f a (Vertex1 x) = x `f ` a
   foldl f a (Vertex1 x) = a `f` x
   foldr1 _ (Vertex1 x) = x
   foldl1 _ (Vertex1 x) = x

instance Traversable Vertex1 where
   traverse f (Vertex1 x) = pure Vertex1 <*> f x
   sequenceA (Vertex1 x) =  pure Vertex1 <*> x
   mapM f (Vertex1 x) = return Vertex1 `ap` f x
   sequence (Vertex1 x) = return Vertex1 `ap` x

instance Typeable1 Vertex1 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vertex1") []

instance Typeable a => Typeable (Vertex1 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vertex1 a) where
   sizeOf    ~(Vertex1 s) = sizeOf s
   alignment ~(Vertex1 s) = alignment s
   peek = peek1 Vertex1 . castPtr
   poke ptr (Vertex1 s) = poke1 (castPtr ptr) s

--------------------------------------------------------------------------------

-- | A vertex with /z/=0 and /w/=1.
data Vertex2 a = Vertex2 !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vertex2 where
   fmap f (Vertex2 x y) = Vertex2 (f x) (f y)

instance Applicative Vertex2 where
   pure a = Vertex2 a a
   Vertex2 f g <*> Vertex2 x y = Vertex2 (f x) (g y)

instance Foldable Vertex2 where
   foldr f a (Vertex2 x y) = x `f ` (y `f` a)
   foldl f a (Vertex2 x y) = (a `f` x) `f` y
   foldr1 f (Vertex2 x y) = x `f` y
   foldl1 f (Vertex2 x y) = x `f` y

instance Traversable Vertex2 where
   traverse f (Vertex2 x y) = pure Vertex2 <*> f x <*> f y
   sequenceA (Vertex2 x y) =  pure Vertex2 <*> x <*> y
   mapM f (Vertex2 x y) = return Vertex2 `ap` f x `ap` f y
   sequence (Vertex2 x y) = return Vertex2 `ap` x `ap` y

instance Typeable1 Vertex2 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vertex2") []

instance Typeable a => Typeable (Vertex2 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vertex2 a) where
   sizeOf ~(Vertex2 x _) = 2 * sizeOf x
   alignment ~(Vertex2 x _) = alignment x
   peek = peek2 Vertex2 . castPtr
   poke ptr (Vertex2 x y) = poke2 (castPtr ptr) x y

--------------------------------------------------------------------------------

-- | A vertex with /w/=1.
data Vertex3 a = Vertex3 !a !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vertex3 where
   fmap f (Vertex3 x y z) = Vertex3 (f x) (f y) (f z)

instance Applicative Vertex3 where
   pure a = Vertex3 a a a
   Vertex3 f g h <*> Vertex3 x y z = Vertex3 (f x) (g y) (h z)

instance Foldable Vertex3 where
   foldr f a (Vertex3 x y z) = x `f ` (y `f` (z `f` a))
   foldl f a (Vertex3 x y z) = ((a `f` x) `f` y) `f` z
   foldr1 f (Vertex3 x y z) = x `f` (y `f` z)
   foldl1 f (Vertex3 x y z) = (x `f` y) `f` z

instance Traversable Vertex3 where
   traverse f (Vertex3 x y z) = pure Vertex3 <*> f x <*> f y <*> f z
   sequenceA (Vertex3 x y z) =  pure Vertex3 <*> x <*> y <*> z
   mapM f (Vertex3 x y z) = return Vertex3 `ap` f x `ap` f y `ap` f z
   sequence (Vertex3 x y z) = return Vertex3 `ap` x `ap` y `ap` z

instance Typeable1 Vertex3 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vertex3") []

instance Typeable a => Typeable (Vertex3 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vertex3 a) where
   sizeOf ~(Vertex3 x _ _) = 3 * sizeOf x
   alignment ~(Vertex3 x _ _) = alignment x
   peek = peek3 Vertex3 . castPtr
   poke ptr (Vertex3 x y z) = poke3 (castPtr ptr) x y z

--------------------------------------------------------------------------------

-- | A fully-fledged four-dimensional vertex.
data Vertex4 a = Vertex4 !a !a !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vertex4 where
   fmap f (Vertex4 x y z w) = Vertex4 (f x) (f y) (f z) (f w)

instance Applicative Vertex4 where
   pure a = Vertex4 a a a a
   Vertex4 f g h i <*> Vertex4 x y z w = Vertex4 (f x) (g y) (h z) (i w)

instance Foldable Vertex4 where
   foldr f a (Vertex4 x y z w) = x `f ` (y `f` (z `f` (w `f` a)))
   foldl f a (Vertex4 x y z w) = (((a `f` x) `f` y) `f` z) `f` w
   foldr1 f (Vertex4 x y z w) = x `f` (y `f` (z `f` w))
   foldl1 f (Vertex4 x y z w) = ((x `f` y) `f` z) `f` w

instance Traversable Vertex4 where
   traverse f (Vertex4 x y z w) = pure Vertex4 <*> f x <*> f y <*> f z <*> f w
   sequenceA (Vertex4 x y z w) =  pure Vertex4 <*> x <*> y <*> z <*> w
   mapM f (Vertex4 x y z w) = return Vertex4 `ap` f x `ap` f y `ap` f z `ap` f w
   sequence (Vertex4 x y z w) = return Vertex4 `ap` x `ap` y `ap` z `ap` w

instance Typeable1 Vertex4 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vertex4") []

instance Typeable a => Typeable (Vertex4 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vertex4 a) where
   sizeOf ~(Vertex4 x _ _ _) = 4 * sizeOf x
   alignment ~(Vertex4 x _ _ _) = alignment x
   peek = peek4 Vertex4 . castPtr
   poke ptr (Vertex4 x y z w) = poke4 (castPtr ptr) x y z w

--------------------------------------------------------------------------------

-- | A one-dimensional vector.
newtype Vector1 a = Vector1 a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vector1 where
   fmap f (Vector1 x) = Vector1 (f x)

instance Applicative Vector1 where
   pure a = Vector1 a
   Vector1 f <*> Vector1 x = Vector1 (f x)

instance Foldable Vector1 where
   foldr f a (Vector1 x) = x `f ` a
   foldl f a (Vector1 x) = a `f` x
   foldr1 _ (Vector1 x) = x
   foldl1 _ (Vector1 x) = x

instance Traversable Vector1 where
   traverse f (Vector1 x) = pure Vector1 <*> f x
   sequenceA (Vector1 x) =  pure Vector1 <*> x
   mapM f (Vector1 x) = return Vector1 `ap` f x
   sequence (Vector1 x) = return Vector1 `ap` x

instance Typeable1 Vector1 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vector1") []

instance Typeable a => Typeable (Vector1 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vector1 a) where
   sizeOf    ~(Vector1 s) = sizeOf s
   alignment ~(Vector1 s) = alignment s
   peek = peek1 Vector1 . castPtr
   poke ptr (Vector1 s) = poke1 (castPtr ptr) s

--------------------------------------------------------------------------------

-- | A two-dimensional vector.
data Vector2 a = Vector2 !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vector2 where
   fmap f (Vector2 x y) = Vector2 (f x) (f y)

instance Applicative Vector2 where
   pure a = Vector2 a a
   Vector2 f g <*> Vector2 x y = Vector2 (f x) (g y)

instance Foldable Vector2 where
   foldr f a (Vector2 x y) = x `f ` (y `f` a)
   foldl f a (Vector2 x y) = (a `f` x) `f` y
   foldr1 f (Vector2 x y) = x `f` y
   foldl1 f (Vector2 x y) = x `f` y

instance Traversable Vector2 where
   traverse f (Vector2 x y) = pure Vector2 <*> f x <*> f y
   sequenceA (Vector2 x y) =  pure Vector2 <*> x <*> y
   mapM f (Vector2 x y) = return Vector2 `ap` f x `ap` f y
   sequence (Vector2 x y) = return Vector2 `ap` x `ap` y

instance Typeable1 Vector2 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vector2") []

instance Typeable a => Typeable (Vector2 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vector2 a) where
   sizeOf ~(Vector2 x _) = 2 * sizeOf x
   alignment ~(Vector2 x _) = alignment x
   peek = peek2 Vector2 . castPtr
   poke ptr (Vector2 x y) = poke2 (castPtr ptr) x y

--------------------------------------------------------------------------------

-- | A three-dimensional vector.
data Vector3 a = Vector3 !a !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vector3 where
   fmap f (Vector3 x y z) = Vector3 (f x) (f y) (f z)

instance Applicative Vector3 where
   pure a = Vector3 a a a
   Vector3 f g h <*> Vector3 x y z = Vector3 (f x) (g y) (h z)

instance Foldable Vector3 where
   foldr f a (Vector3 x y z) = x `f ` (y `f` (z `f` a))
   foldl f a (Vector3 x y z) = ((a `f` x) `f` y) `f` z
   foldr1 f (Vector3 x y z) = x `f` (y `f` z)
   foldl1 f (Vector3 x y z) = (x `f` y) `f` z

instance Traversable Vector3 where
   traverse f (Vector3 x y z) = pure Vector3 <*> f x <*> f y <*> f z
   sequenceA (Vector3 x y z) =  pure Vector3 <*> x <*> y <*> z
   mapM f (Vector3 x y z) = return Vector3 `ap` f x `ap` f y `ap` f z
   sequence (Vector3 x y z) = return Vector3 `ap` x `ap` y `ap` z

instance Typeable1 Vector3 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vector3") []

instance Typeable a => Typeable (Vector3 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vector3 a) where
   sizeOf ~(Vector3 x _ _) = 3 * sizeOf x
   alignment ~(Vector3 x _ _) = alignment x
   peek = peek3 Vector3 . castPtr
   poke ptr (Vector3 x y z) = poke3 (castPtr ptr) x y z

--------------------------------------------------------------------------------

-- | A four-dimensional vector.
data Vector4 a = Vector4 !a !a !a !a
   deriving (Eq, Ord, Ix, Bounded, Show, Read)

instance Functor Vector4 where
   fmap f (Vector4 x y z w) = Vector4 (f x) (f y) (f z) (f w)

instance Applicative Vector4 where
   pure a = Vector4 a a a a
   Vector4 f g h i <*> Vector4 x y z w = Vector4 (f x) (g y) (h z) (i w)

instance Foldable Vector4 where
   foldr f a (Vector4 x y z w) = x `f ` (y `f` (z `f` (w `f` a)))
   foldl f a (Vector4 x y z w) = (((a `f` x) `f` y) `f` z) `f` w
   foldr1 f (Vector4 x y z w) = x `f` (y `f` (z `f` w))
   foldl1 f (Vector4 x y z w) = ((x `f` y) `f` z) `f` w

instance Traversable Vector4 where
   traverse f (Vector4 x y z w) = pure Vector4 <*> f x <*> f y <*> f z <*> f w
   sequenceA (Vector4 x y z w) =  pure Vector4 <*> x <*> y <*> z <*> w
   mapM f (Vector4 x y z w) = return Vector4 `ap` f x `ap` f y `ap` f z `ap` f w
   sequence (Vector4 x y z w) = return Vector4 `ap` x `ap` y `ap` z `ap` w

instance Typeable1 Vector4 where
   typeOf1 _ = mkTyConApp (mkTyCon "Vector4") []

instance Typeable a => Typeable (Vector4 a) where
   typeOf = typeOfDefault

instance Storable a => Storable (Vector4 a) where
   sizeOf ~(Vector4 x _ _ _) = 4 * sizeOf x
   alignment ~(Vector4 x _ _ _) = alignment x
   peek = peek4 Vector4 . castPtr
   poke ptr (Vector4 x y z w) = poke4 (castPtr ptr) x y z w
