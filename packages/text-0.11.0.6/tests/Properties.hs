{-# LANGUAGE BangPatterns, FlexibleInstances, OverloadedStrings,
             ScopedTypeVariables, TypeSynonymInstances #-}
{-# OPTIONS_GHC -fno-enable-rewrite-rules #-}

import Test.QuickCheck
import Test.QuickCheck.Monadic
import Text.Show.Functions ()

import qualified Data.Bits as Bits (shiftL, shiftR)
import Numeric (showHex)
import Data.Char (chr, isDigit, isHexDigit, isLower, isSpace, isUpper, ord)
import Data.Monoid (Monoid(..))
import Data.String (fromString)
import Debug.Trace (trace)
import Control.Arrow ((***), second)
import Control.DeepSeq
import Data.Word (Word8, Word16, Word32)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.IO as TL
import qualified Data.Text.Lazy.Internal as TL
import qualified Data.Text.Lazy.Builder as TB
import qualified Data.Text.Encoding as E
import Data.Text.Read as T
import Data.Text.Lazy.Read as TL
import Data.Text.Encoding.Error
import Control.Exception (SomeException, bracket, catch, evaluate, try)
import Data.Text.Foreign
import qualified Data.Text.Fusion as S
import qualified Data.Text.Fusion.Common as S
import Data.Text.Fusion.Size
import qualified Data.Text.Lazy.Encoding as EL
import qualified Data.Text.Lazy.Fusion as SL
import qualified Data.Text.UnsafeShift as U
import qualified Data.List as L
import Prelude hiding (catch, replicate)
import System.IO
import System.IO.Unsafe (unsafePerformIO)
import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Data.Text.Search (indices)
import qualified Data.Text.Lazy.Search as S (indices)
import qualified SlowFunctions as Slow

import QuickCheckUtils (NotEmpty(..), genUnicode, small, unsquare)
import TestUtils (withRedirect, withTempFile)

-- Ensure that two potentially bottom values (in the sense of crashing
-- for some inputs, not looping infinitely) either both crash, or both
-- give comparable results for some input.
(=^=) :: (Eq a, Show a) => a -> a -> Bool
{-# NOINLINE (=^=) #-}
i =^= j = unsafePerformIO $ do
  x <- try (evaluate i)
  y <- try (evaluate j)
  case (x,y) of
    (Left (_ :: SomeException), Left (_ :: SomeException))
                       -> return True
    (Right a, Right b) -> return (a == b)
    e                  -> trace ("*** Divergence: " ++ show e) return False
infix 4 =^=

t_pack_unpack       = (T.unpack . T.pack) `eq` id
tl_pack_unpack      = (TL.unpack . TL.pack) `eq` id
t_stream_unstream   = (S.unstream . S.stream) `eq` id
tl_stream_unstream  = (SL.unstream . SL.stream) `eq` id
t_reverse_stream t  = (S.reverse . S.reverseStream) t == t
t_singleton c       = [c] == (T.unpack . T.singleton) c
tl_singleton c      = [c] == (TL.unpack . TL.singleton) c
tl_unstreamChunks x = f 11 x == f 1000 x
    where f n = SL.unstreamChunks n . S.streamList
tl_chunk_unchunk    = (TL.fromChunks . TL.toChunks) `eq` id
tl_from_to_strict   = (TL.fromStrict . TL.toStrict) `eq` id

t_ascii t    = E.decodeASCII (E.encodeUtf8 a) == a
    where a  = T.map (\c -> chr (ord c `mod` 128)) t
tl_ascii t   = EL.decodeASCII (EL.encodeUtf8 a) == a
    where a  = TL.map (\c -> chr (ord c `mod` 128)) t
t_utf8       = forAll genUnicode $ (E.decodeUtf8 . E.encodeUtf8) `eq` id
t_utf8'      = forAll genUnicode $ (E.decodeUtf8' . E.encodeUtf8) `eq` (id . Right)
tl_utf8      = forAll genUnicode $ (EL.decodeUtf8 . EL.encodeUtf8) `eq` id
tl_utf8'     = forAll genUnicode $ (EL.decodeUtf8' . EL.encodeUtf8) `eq` (id . Right)
t_utf16LE    = forAll genUnicode $ (E.decodeUtf16LE . E.encodeUtf16LE) `eq` id
tl_utf16LE   = forAll genUnicode $ (EL.decodeUtf16LE . EL.encodeUtf16LE) `eq` id
t_utf16BE    = forAll genUnicode $ (E.decodeUtf16BE . E.encodeUtf16BE) `eq` id
tl_utf16BE   = forAll genUnicode $ (EL.decodeUtf16BE . EL.encodeUtf16BE) `eq` id
t_utf32LE    = forAll genUnicode $ (E.decodeUtf32LE . E.encodeUtf32LE) `eq` id
tl_utf32LE   = forAll genUnicode $ (EL.decodeUtf32LE . EL.encodeUtf32LE) `eq` id
t_utf32BE    = forAll genUnicode $ (E.decodeUtf32BE . E.encodeUtf32BE) `eq` id
tl_utf32BE   = forAll genUnicode $ (EL.decodeUtf32BE . EL.encodeUtf32BE) `eq` id

data DecodeErr = DE String OnDecodeError

instance Show DecodeErr where
    show (DE d _) = "DE " ++ d

instance Arbitrary DecodeErr where
    arbitrary = oneof [ return $ DE "lenient" lenientDecode
                      , return $ DE "ignore" ignore
                      , return $ DE "strict" strictDecode
                      , DE "replace" `fmap` arbitrary ]

-- This is a poor attempt to ensure that the error handling paths on
-- decode are exercised in some way.  Proper testing would be rather
-- more involved.
t_utf8_err (DE _ de) bs = monadicIO $ do
  l <- run $ let len = T.length (E.decodeUtf8With de bs)
             in (len `seq` return (Right len)) `catch`
                (\(e::UnicodeException) -> return (Left e))
  case l of
    Left err -> assert $ length (show err) >= 0
    Right n  -> assert $ n >= 0

t_utf8_err' bs = monadicIO . assert $ case E.decodeUtf8' bs of
                                        Left err -> length (show err) >= 0
                                        Right t  -> T.length t >= 0

class Stringy s where
    packS    :: String -> s
    unpackS  :: s -> String
    splitAtS :: Int -> s -> (s,s)
    packSChunkSize :: Int -> String -> s
    packSChunkSize _ = packS

instance Stringy String where
    packS    = id
    unpackS  = id
    splitAtS = splitAt

instance Stringy (S.Stream Char) where
    packS        = S.streamList
    unpackS      = S.unstreamList
    splitAtS n s = (S.take n s, S.drop n s)

instance Stringy T.Text where
    packS    = T.pack
    unpackS  = T.unpack
    splitAtS = T.splitAt

instance Stringy TL.Text where
    packSChunkSize k = SL.unstreamChunks k . S.streamList
    packS    = TL.pack
    unpackS  = TL.unpack
    splitAtS = ((TL.lazyInvariant *** TL.lazyInvariant) .) .
               TL.splitAt . fromIntegral

-- Do two functions give the same answer?
eq :: (Eq a, Show a) => (t -> a) -> (t -> a) -> t -> Bool
eq a b s  = a s =^= b s

-- What about with the RHS packed?
eqP :: (Eq a, Show a, Stringy s) =>
       (String -> a) -> (s -> a) -> String -> Word8 -> Bool
eqP f g s w  = eql "orig" (f s) (g t) &&
               eql "mini" (f s) (g mini) &&
               eql "head" (f sa) (g ta) &&
               eql "tail" (f sb) (g tb)
    where t             = packS s
          mini          = packSChunkSize 10 s
          (sa,sb)       = splitAt m s
          (ta,tb)       = splitAtS m t
          l             = length s
          m | l == 0    = n
            | otherwise = n `mod` l
          n             = fromIntegral w
          eql d a b
            | a =^= b   = True
            | otherwise = trace (d ++ ": " ++ show a ++ " /= " ++ show b) False

s_Eq s            = (s==)    `eq` ((S.streamList s==) . S.streamList)
    where _types = s :: String
sf_Eq p s =
    ((L.filter p s==) . L.filter p) `eq`
    (((S.filter p $ S.streamList s)==) . S.filter p . S.streamList)
t_Eq s            = (s==)    `eq` ((T.pack s==) . T.pack)
tl_Eq s           = (s==)    `eq` ((TL.pack s==) . TL.pack)
s_Ord s           = (compare s) `eq` (compare (S.streamList s) . S.streamList)
    where _types = s :: String
sf_Ord p s =
    ((compare $ L.filter p s) . L.filter p) `eq`
    (compare (S.filter p $ S.streamList s) . S.filter p . S.streamList)
t_Ord s           = (compare s) `eq` (compare (T.pack s) . T.pack)
tl_Ord s          = (compare s) `eq` (compare (TL.pack s) . TL.pack)
t_Read            = id       `eq` (T.unpack . read . show)
tl_Read           = id       `eq` (TL.unpack . read . show)
t_Show            = show     `eq` (show . T.pack)
tl_Show           = show     `eq` (show . TL.pack)
t_mappend s       = mappend s`eqP` (unpackS . mappend (T.pack s))
tl_mappend s      = mappend s`eqP` (unpackS . mappend (TL.pack s))
t_mconcat         = mconcat `eq` (unpackS . mconcat . L.map T.pack)
tl_mconcat        = mconcat `eq` (unpackS . mconcat . L.map TL.pack)
t_mempty          = mempty == (unpackS (mempty :: T.Text))
tl_mempty         = mempty == (unpackS (mempty :: TL.Text))
t_IsString        = fromString  `eqP` (T.unpack . fromString)
tl_IsString       = fromString  `eqP` (TL.unpack . fromString)

s_cons x          = (x:)     `eqP` (unpackS . S.cons x)
s_cons_s x        = (x:)     `eqP` (unpackS . S.unstream . S.cons x)
sf_cons p x       = ((x:) . L.filter p) `eqP` (unpackS . S.cons x . S.filter p)
t_cons x          = (x:)     `eqP` (unpackS . T.cons x)
tl_cons x         = (x:)     `eqP` (unpackS . TL.cons x)
s_snoc x          = (++ [x]) `eqP` (unpackS . (flip S.snoc) x)
t_snoc x          = (++ [x]) `eqP` (unpackS . (flip T.snoc) x)
tl_snoc x         = (++ [x]) `eqP` (unpackS . (flip TL.snoc) x)
s_append s        = (s++)    `eqP` (unpackS . S.append (S.streamList s))
s_append_s s      = (s++)    `eqP`
                    (unpackS . S.unstream . S.append (S.streamList s))
sf_append p s     = (L.filter p s++) `eqP`
                    (unpackS . S.append (S.filter p $ S.streamList s))
t_append s        = (s++)    `eqP` (unpackS . T.append (packS s))

uncons (x:xs) = Just (x,xs)
uncons _      = Nothing

s_uncons          = uncons   `eqP` (fmap (second unpackS) . S.uncons)
sf_uncons p       = (uncons . L.filter p) `eqP`
                    (fmap (second unpackS) . S.uncons . S.filter p)
t_uncons          = uncons   `eqP` (fmap (second unpackS) . T.uncons)
tl_uncons         = uncons   `eqP` (fmap (second unpackS) . TL.uncons)
s_head            = head   `eqP` S.head
sf_head p         = (head . L.filter p) `eqP` (S.head . S.filter p)
t_head            = head   `eqP` T.head
tl_head           = head   `eqP` TL.head
s_last            = last   `eqP` S.last
sf_last p         = (last . L.filter p) `eqP` (S.last . S.filter p)
t_last            = last   `eqP` T.last
tl_last           = last   `eqP` TL.last
s_tail            = tail   `eqP` (unpackS . S.tail)
s_tail_s          = tail   `eqP` (unpackS . S.unstream . S.tail)
sf_tail p         = (tail . L.filter p) `eqP` (unpackS . S.tail . S.filter p)
t_tail            = tail   `eqP` (unpackS . T.tail)
tl_tail           = tail   `eqP` (unpackS . TL.tail)
s_init            = init   `eqP` (unpackS . S.init)
s_init_s          = init   `eqP` (unpackS . S.unstream . S.init)
sf_init p         = (init . L.filter p) `eqP` (unpackS . S.init . S.filter p)
t_init            = init   `eqP` (unpackS . T.init)
tl_init           = init   `eqP` (unpackS . TL.init)
s_null            = null   `eqP` S.null
sf_null p         = (null . L.filter p) `eqP` (S.null . S.filter p)
t_null            = null   `eqP` T.null
tl_null           = null   `eqP` TL.null
s_length          = length `eqP` S.length
sf_length p       = (length . L.filter p) `eqP` (S.length . S.filter p)
sl_length         = (fromIntegral . length) `eqP` SL.length
t_length          = length `eqP` T.length
tl_length         = L.genericLength `eqP` TL.length
t_compareLength t = (compare (T.length t)) `eq` T.compareLength t
tl_compareLength t= (compare (TL.length t)) `eq` TL.compareLength t

s_map f           = map f  `eqP` (unpackS . S.map f)
s_map_s f         = map f  `eqP` (unpackS . S.unstream . S.map f)
sf_map p f        = (map f . L.filter p)  `eqP` (unpackS . S.map f . S.filter p)
t_map f           = map f  `eqP` (unpackS . T.map f)
tl_map f          = map f  `eqP` (unpackS . TL.map f)
t_intercalate c   = L.intercalate c `eq`
                    (unpackS . T.intercalate (packS c) . map packS)
tl_intercalate c  = L.intercalate c `eq`
                    (unpackS . TL.intercalate (TL.pack c) . map TL.pack)
s_intersperse c   = L.intersperse c `eqP`
                    (unpackS . S.intersperse c)
s_intersperse_s c = L.intersperse c `eqP`
                    (unpackS . S.unstream . S.intersperse c)
sf_intersperse p c= (L.intersperse c . L.filter p) `eqP`
                   (unpackS . S.intersperse c . S.filter p)
t_intersperse c   = L.intersperse c `eqP` (unpackS . T.intersperse c)
tl_intersperse c  = L.intersperse c `eqP` (unpackS . TL.intersperse c)
t_transpose       = L.transpose `eq` (map unpackS . T.transpose . map packS)
tl_transpose      = L.transpose `eq` (map unpackS . TL.transpose . map TL.pack)
t_reverse         = L.reverse `eqP` (unpackS . T.reverse)
tl_reverse        = L.reverse `eqP` (unpackS . TL.reverse)
t_reverse_short n = L.reverse `eqP` (unpackS . S.reverse . shorten n . S.stream)

t_replace s d     = (L.intercalate d . splitOn s) `eqP`
                    (unpackS . T.replace (T.pack s) (T.pack d))
tl_replace s d     = (L.intercalate d . splitOn s) `eqP`
                     (unpackS . TL.replace (TL.pack s) (TL.pack d))

splitOn :: (Eq a) => [a] -> [a] -> [[a]]
splitOn pat src0
    | l == 0    = error "empty"
    | otherwise = go src0
  where
    l           = length pat
    go src      = search 0 src
      where
        search _ [] = [src]
        search !n s@(_:s')
            | pat `L.isPrefixOf` s = take n src : go (drop l s)
            | otherwise            = search (n+1) s'

s_toCaseFold_length xs = S.length (S.toCaseFold s) >= length xs
    where s = S.streamList xs
sf_toCaseFold_length p xs =
    (S.length . S.toCaseFold . S.filter p $ s) >= (length . L.filter p $ xs)
    where s = S.streamList xs
t_toCaseFold_length t = T.length (T.toCaseFold t) >= T.length t
tl_toCaseFold_length t = TL.length (TL.toCaseFold t) >= TL.length t
t_toLower_length t = T.length (T.toLower t) >= T.length t
t_toLower_lower t = p (T.toLower t) >= p t
    where p = T.length . T.filter isLower
tl_toLower_lower t = p (TL.toLower t) >= p t
    where p = TL.length . TL.filter isLower
t_toUpper_length t = T.length (T.toUpper t) >= T.length t
t_toUpper_upper t = p (T.toUpper t) >= p t
    where p = T.length . T.filter isUpper
tl_toUpper_upper t = p (TL.toUpper t) >= p t
    where p = TL.length . TL.filter isUpper

justifyLeft k c xs  = xs ++ L.replicate (k - length xs) c
justifyRight m n xs = L.replicate (m - length xs) n ++ xs
center k c xs
    | len >= k  = xs
    | otherwise = L.replicate l c ++ xs ++ L.replicate r c
   where len = length xs
         d   = k - len
         r   = d `div` 2
         l   = d - r

s_justifyLeft k c = justifyLeft j c `eqP` (unpackS . S.justifyLeftI j c)
    where j = fromIntegral (k :: Word8)
s_justifyLeft_s k c = justifyLeft j c `eqP`
                      (unpackS . S.unstream . S.justifyLeftI j c)
    where j = fromIntegral (k :: Word8)
sf_justifyLeft p k c = (justifyLeft j c . L.filter p) `eqP`
                       (unpackS . S.justifyLeftI j c . S.filter p)
    where j = fromIntegral (k :: Word8)
t_justifyLeft k c = justifyLeft j c `eqP` (unpackS . T.justifyLeft j c)
    where j = fromIntegral (k :: Word8)
tl_justifyLeft k c = justifyLeft j c `eqP`
                     (unpackS . TL.justifyLeft (fromIntegral j) c)
    where j = fromIntegral (k :: Word8)
t_justifyRight k c = justifyRight j c `eqP` (unpackS . T.justifyRight j c)
    where j = fromIntegral (k :: Word8)
tl_justifyRight k c = justifyRight j c `eqP`
                      (unpackS . TL.justifyRight (fromIntegral j) c)
    where j = fromIntegral (k :: Word8)
t_center k c = center j c `eqP` (unpackS . T.center j c)
    where j = fromIntegral (k :: Word8)
tl_center k c = center j c `eqP` (unpackS . TL.center (fromIntegral j) c)
    where j = fromIntegral (k :: Word8)

sf_foldl p f z    = (L.foldl f z . L.filter p) `eqP` (S.foldl f z . S.filter p)
    where _types  = f :: Char -> Char -> Char
t_foldl f z       = L.foldl f z  `eqP` (T.foldl f z)
    where _types  = f :: Char -> Char -> Char
tl_foldl f z      = L.foldl f z  `eqP` (TL.foldl f z)
    where _types  = f :: Char -> Char -> Char
sf_foldl' p f z   = (L.foldl' f z . L.filter p) `eqP`
                    (S.foldl' f z . S.filter p)
    where _types  = f :: Char -> Char -> Char
t_foldl' f z      = L.foldl' f z `eqP` T.foldl' f z
    where _types  = f :: Char -> Char -> Char
tl_foldl' f z     = L.foldl' f z `eqP` TL.foldl' f z
    where _types  = f :: Char -> Char -> Char
sf_foldl1 p f     = (L.foldl1 f . L.filter p) `eqP` (S.foldl1 f . S.filter p)
t_foldl1 f        = L.foldl1 f   `eqP` T.foldl1 f
tl_foldl1 f       = L.foldl1 f   `eqP` TL.foldl1 f
sf_foldl1' p f    = (L.foldl1' f . L.filter p) `eqP` (S.foldl1' f . S.filter p)
t_foldl1' f       = L.foldl1' f  `eqP` T.foldl1' f
tl_foldl1' f      = L.foldl1' f  `eqP` TL.foldl1' f
sf_foldr p f z    = (L.foldr f z . L.filter p) `eqP` (S.foldr f z . S.filter p)
    where _types  = f :: Char -> Char -> Char
t_foldr f z       = L.foldr f z  `eqP` T.foldr f z
    where _types  = f :: Char -> Char -> Char
tl_foldr f z      = L.foldr f z  `eqP` TL.foldr f z
    where _types  = f :: Char -> Char -> Char
sf_foldr1 p f     = (L.foldr1 f . L.filter p) `eqP` (S.foldr1 f . S.filter p)
t_foldr1 f        = L.foldr1 f   `eqP` T.foldr1 f
tl_foldr1 f       = L.foldr1 f   `eqP` TL.foldr1 f

s_concat_s        = L.concat `eq` (unpackS . S.unstream . S.concat . map packS)
sf_concat p       = (L.concat . map (L.filter p)) `eq`
                    (unpackS . S.concat . map (S.filter p . packS))
t_concat          = L.concat `eq` (unpackS . T.concat . map packS)
tl_concat         = L.concat `eq` (unpackS . TL.concat . map TL.pack)
sf_concatMap p f  = unsquare $ (L.concatMap f . L.filter p) `eqP`
                               (unpackS . S.concatMap (packS . f) . S.filter p)
t_concatMap f     = unsquare $
                    L.concatMap f `eqP` (unpackS . T.concatMap (packS . f))
tl_concatMap f    = unsquare $
                    L.concatMap f `eqP` (unpackS . TL.concatMap (TL.pack . f))
sf_any q p        = (L.any p . L.filter q) `eqP` (S.any p . S.filter q)
t_any p           = L.any p       `eqP` T.any p
tl_any p          = L.any p       `eqP` TL.any p
sf_all q p        = (L.all p . L.filter q) `eqP` (S.all p . S.filter q)
t_all p           = L.all p       `eqP` T.all p
tl_all p          = L.all p       `eqP` TL.all p
sf_maximum p      = (L.maximum . L.filter p) `eqP` (S.maximum . S.filter p)
t_maximum         = L.maximum     `eqP` T.maximum
tl_maximum        = L.maximum     `eqP` TL.maximum
sf_minimum p      = (L.minimum . L.filter p) `eqP` (S.minimum . S.filter p)
t_minimum         = L.minimum     `eqP` T.minimum
tl_minimum        = L.minimum     `eqP` TL.minimum

sf_scanl p f z    = (L.scanl f z . L.filter p) `eqP`
                    (unpackS . S.scanl f z . S.filter p)
t_scanl f z       = L.scanl f z   `eqP` (unpackS . T.scanl f z)
tl_scanl f z      = L.scanl f z   `eqP` (unpackS . TL.scanl f z)
t_scanl1 f        = L.scanl1 f    `eqP` (unpackS . T.scanl1 f)
tl_scanl1 f       = L.scanl1 f    `eqP` (unpackS . TL.scanl1 f)
t_scanr f z       = L.scanr f z   `eqP` (unpackS . T.scanr f z)
tl_scanr f z      = L.scanr f z   `eqP` (unpackS . TL.scanr f z)
t_scanr1 f        = L.scanr1 f    `eqP` (unpackS . T.scanr1 f)
tl_scanr1 f       = L.scanr1 f    `eqP` (unpackS . TL.scanr1 f)

t_mapAccumL f z   = L.mapAccumL f z `eqP` (second unpackS . T.mapAccumL f z)
    where _types  = f :: Int -> Char -> (Int,Char)
tl_mapAccumL f z  = L.mapAccumL f z `eqP` (second unpackS . TL.mapAccumL f z)
    where _types  = f :: Int -> Char -> (Int,Char)
t_mapAccumR f z   = L.mapAccumR f z `eqP` (second unpackS . T.mapAccumR f z)
    where _types  = f :: Int -> Char -> (Int,Char)
tl_mapAccumR f z  = L.mapAccumR f z `eqP` (second unpackS . TL.mapAccumR f z)
    where _types  = f :: Int -> Char -> (Int,Char)

replicate n l = concat (L.replicate n l)

t_replicate n     = replicate m `eq` (unpackS . T.replicate m . packS)
    where m = fromIntegral (n :: Word8)
tl_replicate n    = replicate m `eq`
                    (unpackS . TL.replicate (fromIntegral m) . packS)
    where m = fromIntegral (n :: Word8)

unf :: Int -> Char -> Maybe (Char, Char)
unf n c | fromEnum c * 100 > n = Nothing
        | otherwise            = Just (c, succ c)

t_unfoldr n       = L.unfoldr (unf m) `eq` (unpackS . T.unfoldr (unf m))
    where m = fromIntegral (n :: Word16)
tl_unfoldr n      = L.unfoldr (unf m) `eq` (unpackS . TL.unfoldr (unf m))
    where m = fromIntegral (n :: Word16)
t_unfoldrN n m    = (L.take i . L.unfoldr (unf j)) `eq`
                         (unpackS . T.unfoldrN i (unf j))
    where i = fromIntegral (n :: Word16)
          j = fromIntegral (m :: Word16)
tl_unfoldrN n m   = (L.take i . L.unfoldr (unf j)) `eq`
                         (unpackS . TL.unfoldrN (fromIntegral i) (unf j))
    where i = fromIntegral (n :: Word16)
          j = fromIntegral (m :: Word16)

unpack2 :: (Stringy s) => (s,s) -> (String,String)
unpack2 = unpackS *** unpackS

s_take n          = L.take n      `eqP` (unpackS . S.take n)
s_take_s m        = L.take n      `eqP` (unpackS . S.unstream . S.take n)
  where n = small m
sf_take p n       = (L.take n . L.filter p) `eqP`
                    (unpackS . S.take n . S.filter p)
t_take n          = L.take n      `eqP` (unpackS . T.take n)
tl_take n         = L.take n      `eqP` (unpackS . TL.take (fromIntegral n))
s_drop n          = L.drop n      `eqP` (unpackS . S.drop n)
s_drop_s m        = L.drop n      `eqP` (unpackS . S.unstream . S.drop n)
  where n = small m
sf_drop p n       = (L.drop n . L.filter p) `eqP`
                    (unpackS . S.drop n . S.filter p)
t_drop n          = L.drop n      `eqP` (unpackS . T.drop n)
tl_drop n         = L.drop n      `eqP` (unpackS . TL.drop (fromIntegral n))
s_take_drop m     = (L.take n . L.drop n) `eqP` (unpackS . S.take n . S.drop n)
  where n = small m
s_take_drop_s m   = (L.take n . L.drop n) `eqP`
                    (unpackS . S.unstream . S.take n . S.drop n)
  where n = small m
s_takeWhile p     = L.takeWhile p `eqP` (unpackS . S.takeWhile p)
s_takeWhile_s p   = L.takeWhile p `eqP` (unpackS . S.unstream . S.takeWhile p)
sf_takeWhile q p  = (L.takeWhile p . L.filter q) `eqP`
                    (unpackS . S.takeWhile p . S.filter q)
t_takeWhile p     = L.takeWhile p `eqP` (unpackS . T.takeWhile p)
tl_takeWhile p    = L.takeWhile p `eqP` (unpackS . TL.takeWhile p)
s_dropWhile p     = L.dropWhile p `eqP` (unpackS . S.dropWhile p)
s_dropWhile_s p   = L.dropWhile p `eqP` (unpackS . S.unstream . S.dropWhile p)
sf_dropWhile q p  = (L.dropWhile p . L.filter q) `eqP`
                    (unpackS . S.dropWhile p . S.filter q)
t_dropWhile p     = L.dropWhile p `eqP` (unpackS . T.dropWhile p)
tl_dropWhile p    = L.dropWhile p `eqP` (unpackS . S.dropWhile p)
t_dropWhileEnd p  = (L.reverse . L.dropWhile p . L.reverse) `eqP`
                    (unpackS . T.dropWhileEnd p)
tl_dropWhileEnd p = (L.reverse . L.dropWhile p . L.reverse) `eqP`
                    (unpackS . TL.dropWhileEnd p)
t_dropAround p    = (L.dropWhile p . L.reverse . L.dropWhile p . L.reverse)
                    `eqP` (unpackS . T.dropAround p)
tl_dropAround p   = (L.dropWhile p . L.reverse . L.dropWhile p . L.reverse)
                    `eqP` (unpackS . TL.dropAround p)
t_stripStart      = T.dropWhile isSpace `eq` T.stripStart
tl_stripStart     = TL.dropWhile isSpace `eq` TL.stripStart
t_stripEnd        = T.dropWhileEnd isSpace `eq` T.stripEnd
tl_stripEnd       = TL.dropWhileEnd isSpace `eq` TL.stripEnd
t_strip           = T.dropAround isSpace `eq` T.strip
tl_strip          = TL.dropAround isSpace `eq` TL.strip
t_splitAt n       = L.splitAt n   `eqP` (unpack2 . T.splitAt n)
tl_splitAt n      = L.splitAt n   `eqP` (unpack2 . TL.splitAt (fromIntegral n))
t_span p        = L.span p      `eqP` (unpack2 . T.span p)
tl_span p       = L.span p      `eqP` (unpack2 . TL.span p)

t_breakOn_id s      = squid `eq` (uncurry T.append . T.breakOn s)
  where squid t | T.null s  = error "empty"
                | otherwise = t
tl_breakOn_id s     = squid `eq` (uncurry TL.append . TL.breakOn s)
  where squid t | TL.null s  = error "empty"
                | otherwise = t
t_breakOn_start (NotEmpty s) t = let (_,m) = T.breakOn s t
                               in T.null m || s `T.isPrefixOf` m
tl_breakOn_start (NotEmpty s) t = let (_,m) = TL.breakOn s t
                                in TL.null m || s `TL.isPrefixOf` m
t_breakOnEnd_end (NotEmpty s) t = let (m,_) = T.breakOnEnd s t
                                in T.null m || s `T.isSuffixOf` m
tl_breakOnEnd_end (NotEmpty s) t = let (m,_) = TL.breakOnEnd s t
                                in TL.null m || s `TL.isSuffixOf` m
t_break p       = L.break p     `eqP` (unpack2 . T.break p)
tl_break p      = L.break p     `eqP` (unpack2 . TL.break p)
t_group           = L.group       `eqP` (map unpackS . T.group)
tl_group          = L.group       `eqP` (map unpackS . TL.group)
t_groupBy p       = L.groupBy p   `eqP` (map unpackS . T.groupBy p)
tl_groupBy p      = L.groupBy p   `eqP` (map unpackS . TL.groupBy p)
t_inits           = L.inits       `eqP` (map unpackS . T.inits)
tl_inits          = L.inits       `eqP` (map unpackS . TL.inits)
t_tails           = L.tails       `eqP` (map unpackS . T.tails)
tl_tails          = L.tails       `eqP` (map unpackS . TL.tails)
t_findAppendId (NotEmpty s) = unsquare $ \ts ->
    let t = T.intercalate s ts
    in all (==t) $ map (uncurry T.append) (T.breakOnAll s t)
tl_findAppendId (NotEmpty s) = unsquare $ \ts ->
    let t = TL.intercalate s ts
    in all (==t) $ map (uncurry TL.append) (TL.breakOnAll s t)
t_findContains (NotEmpty s) = all (T.isPrefixOf s . snd) . T.breakOnAll s .
                              T.intercalate s
tl_findContains (NotEmpty s) = all (TL.isPrefixOf s . snd) .
                               TL.breakOnAll s . TL.intercalate s
sl_filterCount c  = (L.genericLength . L.filter (==c)) `eqP` SL.countChar c
t_findCount s     = (L.length . T.breakOnAll s) `eq` T.count s
tl_findCount s    = (L.genericLength . TL.breakOnAll s) `eq` TL.count s

t_splitOn_split s         = (T.splitOn s `eq` Slow.splitOn s) . T.intercalate s
tl_splitOn_split s        = ((TL.splitOn (TL.fromStrict s) . TL.fromStrict) `eq`
                           (map TL.fromStrict . T.splitOn s)) . T.intercalate s
t_splitOn_i (NotEmpty t)  = id `eq` (T.intercalate t . T.splitOn t)
tl_splitOn_i (NotEmpty t) = id `eq` (TL.intercalate t . TL.splitOn t)

t_split p       = split p `eqP` (map unpackS . T.split p)
t_split_count c = (L.length . T.split (==c)) `eq`
                  ((1+) . T.count (T.singleton c))
t_split_splitOn c = T.split (==c) `eq` T.splitOn (T.singleton c)
tl_split p      = split p `eqP` (map unpackS . TL.split p)

split :: (a -> Bool) -> [a] -> [[a]]
split _ [] =  [[]]
split p xs = loop xs
    where loop s | null s'   = [l]
                 | otherwise = l : loop (tail s')
              where (l, s') = break p s

t_chunksOf_same_lengths k = all ((==k) . T.length) . ini . T.chunksOf k
  where ini [] = []
        ini xs = init xs

t_chunksOf_length k t = len == T.length t || (k <= 0 && len == 0)
  where len = L.sum . L.map T.length $ T.chunksOf k t

tl_chunksOf k = T.chunksOf k `eq` (map (T.concat . TL.toChunks) .
                                   TL.chunksOf (fromIntegral k) . TL.fromStrict)

t_lines           = L.lines       `eqP` (map unpackS . T.lines)
tl_lines          = L.lines       `eqP` (map unpackS . TL.lines)
{-
t_lines'          = lines'        `eqP` (map unpackS . T.lines')
    where lines' "" =  []
          lines' s =  let (l, s') = break eol s
                      in  l : case s' of
                                []      -> []
                                ('\r':'\n':s'') -> lines' s''
                                (_:s'') -> lines' s''
          eol c = c == '\r' || c == '\n'
-}
t_words           = L.words       `eqP` (map unpackS . T.words)

tl_words          = L.words       `eqP` (map unpackS . TL.words)
t_unlines         = L.unlines `eq` (unpackS . T.unlines . map packS)
tl_unlines        = L.unlines `eq` (unpackS . TL.unlines . map packS)
t_unwords         = L.unwords `eq` (unpackS . T.unwords . map packS)
tl_unwords        = L.unwords `eq` (unpackS . TL.unwords . map packS)

s_isPrefixOf s    = L.isPrefixOf s `eqP`
                    (S.isPrefixOf (S.stream $ packS s) . S.stream)
sf_isPrefixOf p s = (L.isPrefixOf s . L.filter p) `eqP`
                    (S.isPrefixOf (S.stream $ packS s) . S.filter p . S.stream)
t_isPrefixOf s    = L.isPrefixOf s`eqP` T.isPrefixOf (packS s)
tl_isPrefixOf s   = L.isPrefixOf s`eqP` TL.isPrefixOf (packS s)
t_isSuffixOf s    = L.isSuffixOf s`eqP` T.isSuffixOf (packS s)
tl_isSuffixOf s   = L.isSuffixOf s`eqP` TL.isSuffixOf (packS s)
t_isInfixOf s     = L.isInfixOf s `eqP` T.isInfixOf (packS s)
tl_isInfixOf s    = L.isInfixOf s `eqP` TL.isInfixOf (packS s)

t_stripPrefix s      = (fmap packS . L.stripPrefix s) `eqP` T.stripPrefix (packS s)
tl_stripPrefix s     = (fmap packS . L.stripPrefix s) `eqP` TL.stripPrefix (packS s)

stripSuffix p t = reverse `fmap` L.stripPrefix (reverse p) (reverse t)

t_stripSuffix s      = (fmap packS . stripSuffix s) `eqP` T.stripSuffix (packS s)
tl_stripSuffix s     = (fmap packS . stripSuffix s) `eqP` TL.stripSuffix (packS s)

commonPrefixes a0@(_:_) b0@(_:_) = Just (go a0 b0 [])
    where go (a:as) (b:bs) ps
              | a == b = go as bs (a:ps)
          go as bs ps  = (reverse ps,as,bs)
commonPrefixes _ _ = Nothing

t_commonPrefixes a b (NonEmpty p)
    = commonPrefixes pa pb ==
      repack `fmap` T.commonPrefixes (packS pa) (packS pb)
  where repack (x,y,z) = (unpackS x,unpackS y,unpackS z)
        pa = p ++ a
        pb = p ++ b

tl_commonPrefixes a b (NonEmpty p)
    = commonPrefixes pa pb ==
      repack `fmap` TL.commonPrefixes (packS pa) (packS pb)
  where repack (x,y,z) = (unpackS x,unpackS y,unpackS z)
        pa = p ++ a
        pb = p ++ b

sf_elem p c       = (L.elem c . L.filter p) `eqP` (S.elem c . S.filter p)
sf_filter q p     = (L.filter p . L.filter q) `eqP`
                    (unpackS . S.filter p . S.filter q)
t_filter p        = L.filter p    `eqP` (unpackS . T.filter p)
tl_filter p       = L.filter p    `eqP` (unpackS . TL.filter p)
sf_findBy q p     = (L.find p . L.filter q) `eqP` (S.findBy p . S.filter q)
t_find p          = L.find p      `eqP` T.find p
tl_find p         = L.find p      `eqP` TL.find p
t_partition p     = L.partition p `eqP` (unpack2 . T.partition p)
tl_partition p    = L.partition p `eqP` (unpack2 . TL.partition p)

sf_index p s      = forAll (choose (-l,l*2))
                    ((L.filter p s L.!!) `eq` S.index (S.filter p $ packS s))
    where l = L.length s
t_index s         = forAll (choose (-l,l*2)) ((s L.!!) `eq` T.index (packS s))
    where l = L.length s

tl_index s        = forAll (choose (-l,l*2))
                    ((s L.!!) `eq` (TL.index (packS s) . fromIntegral))
    where l = L.length s

t_findIndex p     = L.findIndex p `eqP` T.findIndex p
t_count (NotEmpty t)  = (subtract 1 . L.length . T.splitOn t) `eq` T.count t
tl_count (NotEmpty t) = (subtract 1 . L.genericLength . TL.splitOn t) `eq`
                        TL.count t
t_zip s           = L.zip s `eqP` T.zip (packS s)
tl_zip s          = L.zip s `eqP` TL.zip (packS s)
sf_zipWith p c s  = (L.zipWith c (L.filter p s) . L.filter p) `eqP`
                    (unpackS . S.zipWith c (S.filter p $ packS s) . S.filter p)
t_zipWith c s     = L.zipWith c s `eqP` (unpackS . T.zipWith c (packS s))
tl_zipWith c s    = L.zipWith c s `eqP` (unpackS . TL.zipWith c (packS s))

t_indices  (NotEmpty s) = Slow.indices s `eq` indices s
tl_indices (NotEmpty s) = lazyIndices s `eq` S.indices s
    where lazyIndices ss t = map fromIntegral $ Slow.indices (conc ss) (conc t)
          conc = T.concat . TL.toChunks
t_indices_occurs (NotEmpty t) ts = let s = T.intercalate t ts
                                   in Slow.indices t s == indices t s

-- Bit shifts.
shiftL w = forAll (choose (0,width-1)) $ \k -> Bits.shiftL w k == U.shiftL w k
    where width = round (log (fromIntegral m) / log 2 :: Double)
          (m,_) = (maxBound, m == w)
shiftR w = forAll (choose (0,width-1)) $ \k -> Bits.shiftR w k == U.shiftR w k
    where width = round (log (fromIntegral m) / log 2 :: Double)
          (m,_) = (maxBound, m == w)

shiftL_Int    = shiftL :: Int -> Property
shiftL_Word16 = shiftL :: Word16 -> Property
shiftL_Word32 = shiftL :: Word32 -> Property
shiftR_Int    = shiftR :: Int -> Property
shiftR_Word16 = shiftR :: Word16 -> Property
shiftR_Word32 = shiftR :: Word32 -> Property

-- Builder.

t_builderSingleton = id `eqP`
                     (unpackS . TB.toLazyText . mconcat . map TB.singleton)
t_builderFromText = L.concat `eq` (unpackS . TB.toLazyText . mconcat .
                                   map (TB.fromText . packS))
t_builderAssociative s1 s2 s3 =
    TB.toLazyText (b1 `mappend` (b2 `mappend` b3)) ==
    TB.toLazyText ((b1 `mappend` b2) `mappend` b3)
  where b1 = TB.fromText (packS s1)
        b2 = TB.fromText (packS s2)
        b3 = TB.fromText (packS s3)

-- Reading.

t_decimal (n::Int) s =
    T.signed T.decimal (T.pack (show n) `T.append` t) == Right (n,t)
    where t = T.dropWhile isDigit s
tl_decimal (n::Int) s =
    TL.signed TL.decimal (TL.pack (show n) `TL.append` t) == Right (n,t)
    where t = TL.dropWhile isDigit s
t_hexadecimal (n::Positive Int) s ox =
    T.hexadecimal (T.concat [p, T.pack (showHex n ""), t]) == Right (n,t)
    where t = T.dropWhile isHexDigit s
          p = if ox then "0x" else ""
tl_hexadecimal (n::Positive Int) s ox =
    TL.hexadecimal (TL.concat [p, TL.pack (showHex n ""), t]) == Right (n,t)
    where t = TL.dropWhile isHexDigit s
          p = if ox then "0x" else ""

isFloaty c = c `elem` "+-.0123456789eE"

t_read_rational p tol (n::Double) s =
    case p (T.pack (show n) `T.append` t) of
      Left _err     -> False
      Right (n',t') -> t == t' && abs (n-n') <= tol
    where t = T.dropWhile isFloaty s

tl_read_rational p tol (n::Double) s =
    case p (TL.pack (show n) `TL.append` t) of
      Left _err     -> False
      Right (n',t') -> t == t' && abs (n-n') <= tol
    where t = TL.dropWhile isFloaty s

t_double = t_read_rational T.double 1e-13
tl_double = tl_read_rational TL.double 1e-13
t_rational = t_read_rational T.rational 1e-16
tl_rational = tl_read_rational TL.rational 1e-16

-- Input and output.

-- Work around lack of Show instance for TextEncoding.
data Encoding = E String TextEncoding

instance Show Encoding where show (E n _) = "utf" ++ n

instance Arbitrary Encoding where
    arbitrary = oneof . map return $
      [ E "8" utf8, E "8_bom" utf8_bom, E "16" utf16, E "16le" utf16le,
        E "16be" utf16be, E "32" utf32, E "32le" utf32le, E "32be" utf32be ]

windowsNewlineMode  = NewlineMode { inputNL = CRLF, outputNL = CRLF }

instance Show Newline where
    show CRLF = "CRLF"
    show LF   = "LF"

instance Show NewlineMode where
    show (NewlineMode i o) = "NewlineMode { inputNL = " ++ show i ++
                             ", outputNL = " ++ show o ++ " }"

instance Arbitrary NewlineMode where
    arbitrary = oneof . map return $
      [ noNewlineTranslation, universalNewlineMode, nativeNewlineMode,
        windowsNewlineMode ]

instance Arbitrary BufferMode where
    arbitrary = oneof [ return NoBuffering,
                        return LineBuffering,
                        return (BlockBuffering Nothing),
                        (BlockBuffering . Just . (+1) . fromIntegral) `fmap`
                        (arbitrary :: Gen Word16) ]

-- This test harness is complex!  What property are we checking?
--
-- Reading after writing a multi-line file should give the same
-- results as were written.
--
-- What do we vary while checking this property?
-- * The lines themselves, scrubbed to contain neither CR nor LF.  (By
--   working with a list of lines, we ensure that the data will
--   sometimes contain line endings.)
-- * Encoding.
-- * Newline translation mode.
-- * Buffering.
write_read unline filt writer reader (E _ enc) nl buf ts =
    monadicIO $ assert . (==t) =<< run act
  where t = unline . map (filt (not . (`elem` "\r\n"))) $ ts
        act = withTempFile $ \path h -> do
                hSetEncoding h enc
                hSetNewlineMode h nl
                hSetBuffering h buf
                () <- writer h t
                hClose h
                bracket (openFile path ReadMode) hClose $ \h' -> do
                  hSetEncoding h' enc
                  hSetNewlineMode h' nl
                  hSetBuffering h' buf
                  r <- reader h'
                  r `deepseq` return r

t_put_get = write_read T.unlines T.filter put get
  where put h = withRedirect h stdout . T.putStr
        get h = withRedirect h stdin T.getContents
tl_put_get = write_read TL.unlines TL.filter put get
  where put h = withRedirect h stdout . TL.putStr
        get h = withRedirect h stdin TL.getContents
t_write_read = write_read T.unlines T.filter T.hPutStr T.hGetContents
tl_write_read = write_read TL.unlines TL.filter TL.hPutStr TL.hGetContents

t_write_read_line e m b t = write_read head T.filter T.hPutStrLn
                            T.hGetLine e m b [t]
tl_write_read_line e m b t = write_read head TL.filter TL.hPutStrLn
                             TL.hGetLine e m b [t]

-- Low-level.

t_dropWord16 m t = dropWord16 m t `T.isSuffixOf` t
t_takeWord16 m t = takeWord16 m t `T.isPrefixOf` t
t_take_drop_16 m t = T.append (takeWord16 n t) (dropWord16 n t) == t
  where n = small m
t_use_from t = monadicIO $ assert . (==t) =<< run (useAsPtr t fromPtr)

-- Regression tests.
s_filter_eq s = S.filter p t == S.streamList (filter p s)
    where p = (/= S.last t)
          t = S.streamList s

-- Make a stream appear shorter than it really is, to ensure that
-- functions that consume inaccurately sized streams behave
-- themselves.
shorten :: Int -> S.Stream a -> S.Stream a
shorten n t@(S.Stream arr off len)
    | n > 0     = S.Stream arr off (smaller (exactSize n) len) 
    | otherwise = t

main = defaultMain tests

tests = [
  testGroup "creation/elimination" [
    testProperty "t_pack_unpack" t_pack_unpack,
    testProperty "tl_pack_unpack" tl_pack_unpack,
    testProperty "t_stream_unstream" t_stream_unstream,
    testProperty "tl_stream_unstream" tl_stream_unstream,
    testProperty "t_reverse_stream" t_reverse_stream,
    testProperty "t_singleton" t_singleton,
    testProperty "tl_singleton" tl_singleton,
    testProperty "tl_unstreamChunks" tl_unstreamChunks,
    testProperty "tl_chunk_unchunk" tl_chunk_unchunk,
    testProperty "tl_from_to_strict" tl_from_to_strict
  ],

  testGroup "transcoding" [
    testProperty "t_ascii" t_ascii,
    testProperty "tl_ascii" tl_ascii,
    testProperty "t_utf8" t_utf8,
    testProperty "t_utf8'" t_utf8',
    testProperty "tl_utf8" tl_utf8,
    testProperty "tl_utf8'" tl_utf8',
    testProperty "t_utf16LE" t_utf16LE,
    testProperty "tl_utf16LE" tl_utf16LE,
    testProperty "t_utf16BE" t_utf16BE,
    testProperty "tl_utf16BE" tl_utf16BE,
    testProperty "t_utf32LE" t_utf32LE,
    testProperty "tl_utf32LE" tl_utf32LE,
    testProperty "t_utf32BE" t_utf32BE,
    testProperty "tl_utf32BE" tl_utf32BE,
    testGroup "errors" [
      testProperty "t_utf8_err" t_utf8_err,
      testProperty "t_utf8_err'" t_utf8_err'
    ]
  ],

  testGroup "instances" [
    testProperty "s_Eq" s_Eq,
    testProperty "sf_Eq" sf_Eq,
    testProperty "t_Eq" t_Eq,
    testProperty "tl_Eq" tl_Eq,
    testProperty "s_Ord" s_Ord,
    testProperty "sf_Ord" sf_Ord,
    testProperty "t_Ord" t_Ord,
    testProperty "tl_Ord" tl_Ord,
    testProperty "t_Read" t_Read,
    testProperty "tl_Read" tl_Read,
    testProperty "t_Show" t_Show,
    testProperty "tl_Show" tl_Show,
    testProperty "t_mappend" t_mappend,
    testProperty "tl_mappend" tl_mappend,
    testProperty "t_mconcat" t_mconcat,
    testProperty "tl_mconcat" tl_mconcat,
    testProperty "t_mempty" t_mempty,
    testProperty "tl_mempty" tl_mempty,
    testProperty "t_IsString" t_IsString,
    testProperty "tl_IsString" tl_IsString
  ],

  testGroup "basics" [
    testProperty "s_cons" s_cons,
    testProperty "s_cons_s" s_cons_s,
    testProperty "sf_cons" sf_cons,
    testProperty "t_cons" t_cons,
    testProperty "tl_cons" tl_cons,
    testProperty "s_snoc" s_snoc,
    testProperty "t_snoc" t_snoc,
    testProperty "tl_snoc" tl_snoc,
    testProperty "s_append" s_append,
    testProperty "s_append_s" s_append_s,
    testProperty "sf_append" sf_append,
    testProperty "t_append" t_append,
    testProperty "s_uncons" s_uncons,
    testProperty "sf_uncons" sf_uncons,
    testProperty "t_uncons" t_uncons,
    testProperty "tl_uncons" tl_uncons,
    testProperty "s_head" s_head,
    testProperty "sf_head" sf_head,
    testProperty "t_head" t_head,
    testProperty "tl_head" tl_head,
    testProperty "s_last" s_last,
    testProperty "sf_last" sf_last,
    testProperty "t_last" t_last,
    testProperty "tl_last" tl_last,
    testProperty "s_tail" s_tail,
    testProperty "s_tail_s" s_tail_s,
    testProperty "sf_tail" sf_tail,
    testProperty "t_tail" t_tail,
    testProperty "tl_tail" tl_tail,
    testProperty "s_init" s_init,
    testProperty "s_init_s" s_init_s,
    testProperty "sf_init" sf_init,
    testProperty "t_init" t_init,
    testProperty "tl_init" tl_init,
    testProperty "s_null" s_null,
    testProperty "sf_null" sf_null,
    testProperty "t_null" t_null,
    testProperty "tl_null" tl_null,
    testProperty "s_length" s_length,
    testProperty "sf_length" sf_length,
    testProperty "sl_length" sl_length,
    testProperty "t_length" t_length,
    testProperty "tl_length" tl_length,
    testProperty "t_compareLength" t_compareLength,
    testProperty "tl_compareLength" tl_compareLength
  ],

  testGroup "transformations" [
    testProperty "s_map" s_map,
    testProperty "s_map_s" s_map_s,
    testProperty "sf_map" sf_map,
    testProperty "t_map" t_map,
    testProperty "tl_map" tl_map,
    testProperty "t_intercalate" t_intercalate,
    testProperty "tl_intercalate" tl_intercalate,
    testProperty "s_intersperse" s_intersperse,
    testProperty "s_intersperse_s" s_intersperse_s,
    testProperty "sf_intersperse" sf_intersperse,
    testProperty "t_intersperse" t_intersperse,
    testProperty "tl_intersperse" tl_intersperse,
    testProperty "t_transpose" t_transpose,
    testProperty "tl_transpose" tl_transpose,
    testProperty "t_reverse" t_reverse,
    testProperty "tl_reverse" tl_reverse,
    testProperty "t_reverse_short" t_reverse_short,
    testProperty "t_replace" t_replace,
    testProperty "tl_replace" tl_replace,

    testGroup "case conversion" [
      testProperty "s_toCaseFold_length" s_toCaseFold_length,
      testProperty "sf_toCaseFold_length" sf_toCaseFold_length,
      testProperty "t_toCaseFold_length" t_toCaseFold_length,
      testProperty "tl_toCaseFold_length" tl_toCaseFold_length,
      testProperty "t_toLower_length" t_toLower_length,
      testProperty "t_toLower_lower" t_toLower_lower,
      testProperty "tl_toLower_lower" tl_toLower_lower,
      testProperty "t_toUpper_length" t_toUpper_length,
      testProperty "t_toUpper_upper" t_toUpper_upper,
      testProperty "tl_toUpper_upper" tl_toUpper_upper
    ],

    testGroup "justification" [
      testProperty "s_justifyLeft" s_justifyLeft,
      testProperty "s_justifyLeft_s" s_justifyLeft_s,
      testProperty "sf_justifyLeft" sf_justifyLeft,
      testProperty "t_justifyLeft" t_justifyLeft,
      testProperty "tl_justifyLeft" tl_justifyLeft,
      testProperty "t_justifyRight" t_justifyRight,
      testProperty "tl_justifyRight" tl_justifyRight,
      testProperty "t_center" t_center,
      testProperty "tl_center" tl_center
    ]
  ],

  testGroup "folds" [
    testProperty "sf_foldl" sf_foldl,
    testProperty "t_foldl" t_foldl,
    testProperty "tl_foldl" tl_foldl,
    testProperty "sf_foldl'" sf_foldl',
    testProperty "t_foldl'" t_foldl',
    testProperty "tl_foldl'" tl_foldl',
    testProperty "sf_foldl1" sf_foldl1,
    testProperty "t_foldl1" t_foldl1,
    testProperty "tl_foldl1" tl_foldl1,
    testProperty "t_foldl1'" t_foldl1',
    testProperty "sf_foldl1'" sf_foldl1',
    testProperty "tl_foldl1'" tl_foldl1',
    testProperty "sf_foldr" sf_foldr,
    testProperty "t_foldr" t_foldr,
    testProperty "tl_foldr" tl_foldr,
    testProperty "sf_foldr1" sf_foldr1,
    testProperty "t_foldr1" t_foldr1,
    testProperty "tl_foldr1" tl_foldr1,

    testGroup "special" [
      testProperty "s_concat_s" s_concat_s,
      testProperty "sf_concat" sf_concat,
      testProperty "t_concat" t_concat,
      testProperty "tl_concat" tl_concat,
      testProperty "sf_concatMap" sf_concatMap,
      testProperty "t_concatMap" t_concatMap,
      testProperty "tl_concatMap" tl_concatMap,
      testProperty "sf_any" sf_any,
      testProperty "t_any" t_any,
      testProperty "tl_any" tl_any,
      testProperty "sf_all" sf_all,
      testProperty "t_all" t_all,
      testProperty "tl_all" tl_all,
      testProperty "sf_maximum" sf_maximum,
      testProperty "t_maximum" t_maximum,
      testProperty "tl_maximum" tl_maximum,
      testProperty "sf_minimum" sf_minimum,
      testProperty "t_minimum" t_minimum,
      testProperty "tl_minimum" tl_minimum
    ]
  ],

  testGroup "construction" [
    testGroup "scans" [
      testProperty "sf_scanl" sf_scanl,
      testProperty "t_scanl" t_scanl,
      testProperty "tl_scanl" tl_scanl,
      testProperty "t_scanl1" t_scanl1,
      testProperty "tl_scanl1" tl_scanl1,
      testProperty "t_scanr" t_scanr,
      testProperty "tl_scanr" tl_scanr,
      testProperty "t_scanr1" t_scanr1,
      testProperty "tl_scanr1" tl_scanr1
    ],

    testGroup "mapAccum" [
      testProperty "t_mapAccumL" t_mapAccumL,
      testProperty "tl_mapAccumL" tl_mapAccumL,
      testProperty "t_mapAccumR" t_mapAccumR,
      testProperty "tl_mapAccumR" tl_mapAccumR
    ],

    testGroup "unfolds" [
      testProperty "t_replicate" t_replicate,
      testProperty "tl_replicate" tl_replicate,
      testProperty "t_unfoldr" t_unfoldr,
      testProperty "tl_unfoldr" tl_unfoldr,
      testProperty "t_unfoldrN" t_unfoldrN,
      testProperty "tl_unfoldrN" tl_unfoldrN
    ]
  ],

  testGroup "substrings" [
    testGroup "breaking" [
      testProperty "s_take" s_take,
      testProperty "s_take_s" s_take_s,
      testProperty "sf_take" sf_take,
      testProperty "t_take" t_take,
      testProperty "tl_take" tl_take,
      testProperty "s_drop" s_drop,
      testProperty "s_drop_s" s_drop_s,
      testProperty "sf_drop" sf_drop,
      testProperty "t_drop" t_drop,
      testProperty "tl_drop" tl_drop,
      testProperty "s_take_drop" s_take_drop,
      testProperty "s_take_drop_s" s_take_drop_s,
      testProperty "s_takeWhile" s_takeWhile,
      testProperty "s_takeWhile_s" s_takeWhile_s,
      testProperty "sf_takeWhile" sf_takeWhile,
      testProperty "t_takeWhile" t_takeWhile,
      testProperty "tl_takeWhile" tl_takeWhile,
      testProperty "sf_dropWhile" sf_dropWhile,
      testProperty "s_dropWhile" s_dropWhile,
      testProperty "s_dropWhile_s" s_dropWhile_s,
      testProperty "t_dropWhile" t_dropWhile,
      testProperty "tl_dropWhile" tl_dropWhile,
      testProperty "t_dropWhileEnd" t_dropWhileEnd,
      testProperty "tl_dropWhileEnd" tl_dropWhileEnd,
      testProperty "t_dropAround" t_dropAround,
      testProperty "tl_dropAround" tl_dropAround,
      testProperty "t_stripStart" t_stripStart,
      testProperty "tl_stripStart" tl_stripStart,
      testProperty "t_stripEnd" t_stripEnd,
      testProperty "tl_stripEnd" tl_stripEnd,
      testProperty "t_strip" t_strip,
      testProperty "tl_strip" tl_strip,
      testProperty "t_splitAt" t_splitAt,
      testProperty "tl_splitAt" tl_splitAt,
      testProperty "t_span" t_span,
      testProperty "tl_span" tl_span,
      testProperty "t_breakOn_id" t_breakOn_id,
      testProperty "tl_breakOn_id" tl_breakOn_id,
      testProperty "t_breakOn_start" t_breakOn_start,
      testProperty "tl_breakOn_start" tl_breakOn_start,
      testProperty "t_breakOnEnd_end" t_breakOnEnd_end,
      testProperty "tl_breakOnEnd_end" tl_breakOnEnd_end,
      testProperty "t_break" t_break,
      testProperty "tl_break" tl_break,
      testProperty "t_group" t_group,
      testProperty "tl_group" tl_group,
      testProperty "t_groupBy" t_groupBy,
      testProperty "tl_groupBy" tl_groupBy,
      testProperty "t_inits" t_inits,
      testProperty "tl_inits" tl_inits,
      testProperty "t_tails" t_tails,
      testProperty "tl_tails" tl_tails
    ],

    testGroup "breaking many" [
      testProperty "t_findAppendId" t_findAppendId,
      testProperty "tl_findAppendId" tl_findAppendId,
      testProperty "t_findContains" t_findContains,
      testProperty "tl_findContains" tl_findContains,
      testProperty "sl_filterCount" sl_filterCount,
      testProperty "t_findCount" t_findCount,
      testProperty "tl_findCount" tl_findCount,
      testProperty "t_splitOn_split" t_splitOn_split,
      testProperty "tl_splitOn_split" tl_splitOn_split,
      testProperty "t_splitOn_i" t_splitOn_i,
      testProperty "tl_splitOn_i" tl_splitOn_i,
      testProperty "t_split" t_split,
      testProperty "t_split_count" t_split_count,
      testProperty "t_split_splitOn" t_split_splitOn,
      testProperty "tl_split" tl_split,
      testProperty "t_chunksOf_same_lengths" t_chunksOf_same_lengths,
      testProperty "t_chunksOf_length" t_chunksOf_length,
      testProperty "tl_chunksOf" tl_chunksOf
    ],

    testGroup "lines and words" [
      testProperty "t_lines" t_lines,
      testProperty "tl_lines" tl_lines,
    --testProperty "t_lines'" t_lines',
      testProperty "t_words" t_words,
      testProperty "tl_words" tl_words,
      testProperty "t_unlines" t_unlines,
      testProperty "tl_unlines" tl_unlines,
      testProperty "t_unwords" t_unwords,
      testProperty "tl_unwords" tl_unwords
    ]
  ],

  testGroup "predicates" [
    testProperty "s_isPrefixOf" s_isPrefixOf,
    testProperty "sf_isPrefixOf" sf_isPrefixOf,
    testProperty "t_isPrefixOf" t_isPrefixOf,
    testProperty "tl_isPrefixOf" tl_isPrefixOf,
    testProperty "t_isSuffixOf" t_isSuffixOf,
    testProperty "tl_isSuffixOf" tl_isSuffixOf,
    testProperty "t_isInfixOf" t_isInfixOf,
    testProperty "tl_isInfixOf" tl_isInfixOf,

    testGroup "view" [
      testProperty "t_stripPrefix" t_stripPrefix,
      testProperty "tl_stripPrefix" tl_stripPrefix,
      testProperty "t_stripSuffix" t_stripSuffix,
      testProperty "tl_stripSuffix" tl_stripSuffix,
      testProperty "t_commonPrefixes" t_commonPrefixes,
      testProperty "tl_commonPrefixes" tl_commonPrefixes
    ]
  ],

  testGroup "searching" [
    testProperty "sf_elem" sf_elem,
    testProperty "sf_filter" sf_filter,
    testProperty "t_filter" t_filter,
    testProperty "tl_filter" tl_filter,
    testProperty "sf_findBy" sf_findBy,
    testProperty "t_find" t_find,
    testProperty "tl_find" tl_find,
    testProperty "t_partition" t_partition,
    testProperty "tl_partition" tl_partition
  ],

  testGroup "indexing" [
    testProperty "sf_index" sf_index,
    testProperty "t_index" t_index,
    testProperty "tl_index" tl_index,
    testProperty "t_findIndex" t_findIndex,
    testProperty "t_count" t_count,
    testProperty "tl_count" tl_count,
    testProperty "t_indices" t_indices,
    testProperty "tl_indices" tl_indices,
    testProperty "t_indices_occurs" t_indices_occurs
  ],

  testGroup "zips" [
    testProperty "t_zip" t_zip,
    testProperty "tl_zip" tl_zip,
    testProperty "sf_zipWith" sf_zipWith,
    testProperty "t_zipWith" t_zipWith,
    testProperty "tl_zipWith" tl_zipWith
  ],

  testGroup "regressions" [
    testProperty "s_filter_eq" s_filter_eq
  ],

  testGroup "shifts" [
    testProperty "shiftL_Int" shiftL_Int,
    testProperty "shiftL_Word16" shiftL_Word16,
    testProperty "shiftL_Word32" shiftL_Word32,
    testProperty "shiftR_Int" shiftR_Int,
    testProperty "shiftR_Word16" shiftR_Word16,
    testProperty "shiftR_Word32" shiftR_Word32
  ],

  testGroup "builder" [
    testProperty "t_builderSingleton" t_builderSingleton,
    testProperty "t_builderFromText" t_builderFromText,
    testProperty "t_builderAssociative" t_builderAssociative
  ],

  testGroup "read" [
    testProperty "t_decimal" t_decimal,
    testProperty "tl_decimal" tl_decimal,
    testProperty "t_hexadecimal" t_hexadecimal,
    testProperty "tl_hexadecimal" tl_hexadecimal,
    testProperty "t_double" t_double,
    testProperty "tl_double" tl_double,
    testProperty "t_rational" t_rational,
    testProperty "tl_rational" tl_rational
  ],

  testGroup "input-output" [
    testProperty "t_write_read" t_write_read,
    testProperty "tl_write_read" tl_write_read,
    testProperty "t_write_read_line" t_write_read_line,
    testProperty "tl_write_read_line" tl_write_read_line
    -- These tests are subject to I/O race conditions when run under
    -- test-framework-quickcheck2.
    -- testProperty "t_put_get" t_put_get
    -- testProperty "tl_put_get" tl_put_get
  ],

  testGroup "lowlevel" [
    testProperty "t_dropWord16" t_dropWord16,
    testProperty "t_takeWord16" t_takeWord16,
    testProperty "t_take_drop_16" t_take_drop_16,
    testProperty "t_use_from" t_use_from
  ]
 ]
