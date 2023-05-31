{-# LANGUAGE ScopedTypeVariables, BangPatterns, RecordWildCards #-}

{-| Functions used internally by the SDR.Filter module. Most of these are
    not actually used but exist for benchmarking purposes to determine the 
    fastest filter implementation.
-}
module SDR.FilterInternal where

import           Control.Monad.Primitive 
import           Control.Monad
import           Foreign.C.Types
import           Foreign.Ptr
import           Data.Coerce
import           Data.Complex
import           Foreign.Marshal.Array
import           Foreign.Marshal.Alloc
import           Foreign.Storable

import qualified Data.Vector.Generic               as VG
import qualified Data.Vector.Generic.Mutable       as VGM
import qualified Data.Vector.Storable              as VS
import qualified Data.Vector.Storable.Mutable      as VSM
import qualified Data.Vector.Fusion.Bundle         as VFB

import           SDR.VectorUtils
import           SDR.Util

{-# INLINE filterHighLevel #-}
filterHighLevel :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => v b -> Int -> v a -> vm (PrimState m) a -> m ()
filterHighLevel coeffs num inBuf outBuf = fill (VFB.generate num dotProd) outBuf
    where
    dotProd offset = VG.sum $ VG.zipWith mult (VG.unsafeDrop offset inBuf) coeffs

{-# INLINE filterImperative1 #-}
filterImperative1 :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => v b -> Int -> v a -> vm (PrimState m) a -> m ()
filterImperative1 coeffs num inBuf outBuf = go 0
    where
    go offset 
        | offset < num = do
            let res = dotProd offset
            VGM.unsafeWrite outBuf offset res
            go $ offset + 1
        | otherwise    = return ()
    dotProd offset = VG.sum $ VG.zipWith mult (VG.unsafeDrop offset inBuf) coeffs

{-# INLINE filterImperative2 #-}
filterImperative2 :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => v b -> Int -> v a -> vm (PrimState m) a -> m ()
filterImperative2 coeffs num inBuf outBuf = go 0
    where
    go offset 
        | offset < num = do
            let res = dotProd (VG.unsafeDrop offset inBuf)
            VGM.unsafeWrite outBuf offset res
            go $ offset + 1
        | otherwise    = return ()
    dotProd buf = go 0 0
        where
        go !accum j 
            | j < VG.length coeffs = go (VG.unsafeIndex buf j `mult` VG.unsafeIndex coeffs j  + accum) (j + 1)
            | otherwise            = accum

type FilterCRR = CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()
type FilterRR  = VS.Vector Float -> Int -> VS.Vector Float -> VS.MVector RealWorld Float -> IO ()
type FilterRC  = VS.Vector Float -> Int -> VS.Vector (Complex Float) -> VS.MVector RealWorld (Complex Float) -> IO ()

filterFFIR :: FilterCRR -> FilterRR 
filterFFIR func coeffs num inBuf outBuf = 
    VS.unsafeWith (VS.unsafeCoerceVector coeffs) $ \cPtr -> 
        VS.unsafeWith (VS.unsafeCoerceVector inBuf) $ \iPtr -> 
            VSM.unsafeWith (VSM.unsafeCoerceMVector outBuf) $ \oPtr -> 
                func (fromIntegral num) (fromIntegral $ VG.length coeffs) cPtr iPtr oPtr

filterFFIC :: FilterCRR -> FilterRC 
filterFFIC func coeffs num inBuf outBuf = 
    VS.unsafeWith (VS.unsafeCoerceVector coeffs) $ \cPtr -> 
        VS.unsafeWith (VS.unsafeCast inBuf) $ \iPtr -> 
            VSM.unsafeWith (VSM.unsafeCast outBuf) $ \oPtr -> 
                func (fromIntegral num) (fromIntegral $ VG.length coeffs) cPtr iPtr oPtr

foreign import ccall unsafe "filterRR"
    filterRR_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCRR :: FilterRR
filterCRR = filterFFIR filterRR_c 

foreign import ccall unsafe "filterRC"
    filterRC_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCRC :: FilterRC
filterCRC = filterFFIC filterRC_c

foreign import ccall unsafe "filterSSERR"
    filterSSERR_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCSSERR :: FilterRR
filterCSSERR = filterFFIR filterSSERR_c

foreign import ccall unsafe "filterSSESymmetricRR"
    filterSSESymmetricRR_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCSSESymmetricRR :: FilterRR
filterCSSESymmetricRR = filterFFIR filterSSESymmetricRR_c

foreign import ccall unsafe "filterSSERC"
    filterSSERC_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCSSERC :: FilterRC
filterCSSERC = filterFFIC filterSSERC_c

foreign import ccall unsafe "filterSSERC2"
    filterSSERC2_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCSSERC2 :: FilterRC
filterCSSERC2 = filterFFIC filterSSERC2_c

foreign import ccall unsafe "filterAVXRR"
    filterAVXRR_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCAVXRR :: FilterRR
filterCAVXRR = filterFFIR filterAVXRR_c

foreign import ccall unsafe "filterAVXSymmetricRR"
    filterAVXSymmetricRR_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCAVXSymmetricRR :: FilterRR
filterCAVXSymmetricRR = filterFFIR filterAVXSymmetricRR_c

foreign import ccall unsafe "filterAVXRC"
    filterAVXRC_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCAVXRC :: FilterRC
filterCAVXRC = filterFFIC filterAVXRC_c

foreign import ccall unsafe "filterAVXRC2"
    filterAVXRC2_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCAVXRC2 :: FilterRC
filterCAVXRC2 = filterFFIC filterAVXRC2_c

foreign import ccall unsafe "filterSSESymmetricRC"
    filterSSESymmetricRC_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCSSESymmetricRC :: FilterRC
filterCSSESymmetricRC = filterFFIC filterSSESymmetricRC_c

foreign import ccall unsafe "filterAVXSymmetricRC"
    filterAVXSymmetricRC_c :: CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

filterCAVXSymmetricRC :: FilterRC
filterCAVXSymmetricRC = filterFFIC filterAVXSymmetricRC_c

-- Decimation

{-# INLINE decimateHighLevel #-}
decimateHighLevel :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => Int -> v b -> Int -> v a -> vm (PrimState m) a -> m ()
decimateHighLevel factor coeffs num inBuf outBuf = fill x outBuf
    where 
    x = VFB.map dotProd (VFB.iterateN num (+ factor) 0)
    dotProd offset = VG.sum $ VG.zipWith mult (VG.unsafeDrop offset inBuf) coeffs

type DecimateCRR = CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()
type DecimateRR  = Int -> VS.Vector Float -> Int -> VS.Vector Float -> VS.MVector RealWorld Float -> IO ()
type DecimateRC  = Int -> VS.Vector Float -> Int -> VS.Vector (Complex Float) -> VS.MVector RealWorld (Complex Float) -> IO ()

decimateFFIR :: DecimateCRR -> DecimateRR 
decimateFFIR func factor coeffs num inBuf outBuf = 
    VS.unsafeWith (VS.unsafeCoerceVector coeffs) $ \cPtr -> 
        VS.unsafeWith (VS.unsafeCoerceVector inBuf) $ \iPtr -> 
            VSM.unsafeWith (VSM.unsafeCoerceMVector outBuf) $ \oPtr -> 
                func (fromIntegral num) (fromIntegral factor) (fromIntegral $ VG.length coeffs) cPtr iPtr oPtr

decimateFFIC :: DecimateCRR -> DecimateRC 
decimateFFIC func factor coeffs num inBuf outBuf = 
    VS.unsafeWith (VS.unsafeCoerceVector coeffs) $ \cPtr -> 
        VS.unsafeWith (VS.unsafeCast inBuf) $ \iPtr -> 
            VSM.unsafeWith (VSM.unsafeCast outBuf) $ \oPtr -> 
                func (fromIntegral num) (fromIntegral factor) (fromIntegral $ VG.length coeffs) cPtr iPtr oPtr

foreign import ccall unsafe "decimateRR"
    decimateCRR_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCRR :: DecimateRR
decimateCRR = decimateFFIR decimateCRR_c

foreign import ccall unsafe "decimateRC"
    decimateCRC_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCRC :: DecimateRC
decimateCRC = decimateFFIC decimateCRC_c

foreign import ccall unsafe "decimateSSERR"
    decimateSSERR_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCSSERR :: DecimateRR
decimateCSSERR = decimateFFIR decimateSSERR_c

foreign import ccall unsafe "decimateSSERC"
    decimateSSERC_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCSSERC :: DecimateRC
decimateCSSERC = decimateFFIC decimateSSERC_c

foreign import ccall unsafe "decimateSSERC2"
    decimateSSERC2_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCSSERC2 :: DecimateRC
decimateCSSERC2 = decimateFFIC decimateSSERC2_c

foreign import ccall unsafe "decimateAVXRR"
    decimateAVXRR_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCAVXRR :: DecimateRR
decimateCAVXRR = decimateFFIR decimateAVXRR_c

foreign import ccall unsafe "decimateAVXRC"
    decimateAVXRC_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCAVXRC :: DecimateRC
decimateCAVXRC = decimateFFIC decimateAVXRC_c

foreign import ccall unsafe "decimateAVXRC2"
    decimateAVXRC2_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCAVXRC2 :: DecimateRC
decimateCAVXRC2 = decimateFFIC decimateAVXRC2_c

foreign import ccall unsafe "decimateSSESymmetricRR"
    decimateSSESymmetricRR_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCSSESymmetricRR :: DecimateRR
decimateCSSESymmetricRR = decimateFFIR decimateSSESymmetricRR_c

foreign import ccall unsafe "decimateAVXSymmetricRR"
    decimateAVXSymmetricRR_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCAVXSymmetricRR :: DecimateRR
decimateCAVXSymmetricRR = decimateFFIR decimateAVXSymmetricRR_c

foreign import ccall unsafe "decimateSSESymmetricRC"
    decimateSSESymmetricRC_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCSSESymmetricRC :: DecimateRC
decimateCSSESymmetricRC = decimateFFIC decimateSSESymmetricRC_c

foreign import ccall unsafe "decimateAVXSymmetricRC"
    decimateAVXSymmetricRC_c :: CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

decimateCAVXSymmetricRC :: DecimateRC
decimateCAVXSymmetricRC = decimateFFIC decimateAVXSymmetricRC_c

-- Resampling
{-# INLINE resampleHighLevel #-}
resampleHighLevel :: (PrimMonad m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => Int -> Int -> v b -> Int -> Int -> v a -> vm (PrimState m) a -> m Int
resampleHighLevel interpolation decimation coeffs filterOffset count inBuf outBuf = fill 0 filterOffset 0
    where
    fill i filterOffset inputOffset
        | i < count = do
            let dp = dotProd filterOffset inputOffset
            VGM.unsafeWrite outBuf i dp
            let (q, r)        = divMod (decimation - filterOffset - 1) interpolation
                inputOffset'  = inputOffset + q + 1
                filterOffset' = interpolation - 1 - r
            filterOffset' `seq` inputOffset' `seq` fill (i + 1) filterOffset' inputOffset'
        | otherwise = return filterOffset
    dotProd filterOffset offset = VG.sum $ VG.zipWith mult (VG.unsafeDrop offset inBuf) (stride interpolation (VG.unsafeDrop filterOffset coeffs))

foreign import ccall unsafe "resampleRR"
    resample_c :: CInt -> CInt -> CInt -> CInt -> CInt -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

resampleCRR :: Int -> Int -> Int -> Int -> VS.Vector Float -> VS.Vector Float -> VS.MVector RealWorld Float -> IO ()
resampleCRR num interpolation decimation offset coeffs inBuf outBuf = 
    VS.unsafeWith (VS.unsafeCoerceVector coeffs) $ \cPtr -> 
        VS.unsafeWith (VS.unsafeCoerceVector inBuf) $ \iPtr -> 
            VSM.unsafeWith (VSM.unsafeCoerceMVector outBuf) $ \oPtr -> 
                resample_c (fromIntegral num) (fromIntegral $ VG.length coeffs) (fromIntegral interpolation) (fromIntegral decimation) (fromIntegral offset) cPtr iPtr oPtr

pad :: a -> Int -> [a] -> [a]
pad with num list = list ++ replicate (num - length list) with 

strideList :: Int -> [a] -> [a]
strideList s xs = go 0 xs
    where
    go _ []     = []
    go 0 (x:xs) = x : go (s-1) xs
    go n (x:xs) = go (n - 1) xs

roundUp :: Int -> Int -> Int
roundUp num div = ((num + div - 1) `quot` div) * div

data Coeffs = Coeffs {
    numCoeffs  :: Int,
    numGroups  :: Int,
    increments :: [Int],
    groups     :: [[Float]]
}

prepareCoeffs :: Int -> Int -> Int -> [Float] -> Coeffs
prepareCoeffs n interpolation decimation coeffs = Coeffs {..}
    where
    numCoeffs   = maximum $ map (length . snd) dats
    numGroups   = length groups
    increments  = map fst dats

    groups      :: [[Float]]
    groups      = map (pad 0 (roundUp numCoeffs n)) $ map snd dats

    dats :: [(Int, [Float])]
    dats = func 0
        where

        func' 0      = []
        func' x      = func x

        func :: Int -> [(Int, [Float])]
        func offset = (increment, strideList interpolation $ drop offset coeffs) : func' offset'
            where
            (q, r)    = divMod (decimation - offset - 1) interpolation
            increment = q + 1
            offset'   = interpolation - 1 - r

resampleFFIR :: (Ptr CFloat -> Ptr CFloat -> IO CInt) -> VS.Vector Float -> VSM.MVector RealWorld Float -> IO Int
resampleFFIR func inBuf outBuf = liftM fromIntegral $
    VS.unsafeWith (VS.unsafeCoerceVector inBuf) $ \iPtr -> 
        VSM.unsafeWith (VSM.unsafeCoerceMVector outBuf) $ \oPtr -> 
            func iPtr oPtr

resampleFFIC :: (Ptr CFloat -> Ptr CFloat -> IO CInt) -> VS.Vector (Complex Float) -> VSM.MVector RealWorld (Complex Float) -> IO Int
resampleFFIC func inBuf outBuf = liftM fromIntegral $
    VS.unsafeWith (VS.unsafeCast inBuf) $ \iPtr -> 
        VSM.unsafeWith (VSM.unsafeCast outBuf) $ \oPtr -> 
            func iPtr oPtr

type ResampleR = CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

mkResampler :: ResampleR -> Int -> Int -> Int -> [Float] -> IO (Int -> Int -> VS.Vector Float -> VS.MVector RealWorld Float -> IO Int)
mkResampler func n interpolation decimation coeffs = do
    groupsP     <- mapM newArray $ map (map realToFrac) groups
    groupsPP    <- newArray groupsP
    incrementsP <- newArray $ map fromIntegral increments
    return $ \offset num -> resampleFFIR $ func (fromIntegral num) (fromIntegral numCoeffs) (fromIntegral offset) (fromIntegral numGroups) incrementsP groupsPP
    where
    Coeffs {..} = prepareCoeffs n interpolation decimation coeffs

type ResampleRR = Int -> Int -> [Float] -> IO (Int -> Int -> VS.Vector Float -> VS.MVector RealWorld Float -> IO Int)

foreign import ccall unsafe "resample2RR"
    resample2_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCRR2 :: ResampleRR
resampleCRR2 = mkResampler resample2_c 1

foreign import ccall unsafe "resampleSSERR"
    resampleCSSERR_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCSSERR :: ResampleRR
resampleCSSERR = mkResampler resampleCSSERR_c 4

foreign import ccall unsafe "resampleAVXRR"
    resampleAVXRR_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCAVXRR :: ResampleRR
resampleCAVXRR = mkResampler resampleAVXRR_c 8

type ResampleRC = Int -> Int -> [Float] -> IO (Int -> Int -> VS.Vector (Complex Float) -> VS.MVector RealWorld (Complex Float) -> IO Int)

mkResamplerC :: ResampleR -> Int -> Int -> Int -> [Float] -> IO (Int -> Int -> VS.Vector (Complex Float) -> VS.MVector RealWorld (Complex Float) -> IO Int)
mkResamplerC func n interpolation decimation coeffs = do
    groupsP     <- mapM newArray $ map (map realToFrac) groups
    groupsPP    <- newArray groupsP
    incrementsP <- newArray $ map fromIntegral increments
    return $ \offset num -> resampleFFIC $ func (fromIntegral num) (fromIntegral numCoeffs) (fromIntegral offset) (fromIntegral numGroups) incrementsP groupsPP
    where
    Coeffs {..} = prepareCoeffs n interpolation decimation coeffs

foreign import ccall unsafe "resample2RC"
    resample2RC_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCRC :: ResampleRC
resampleCRC = mkResamplerC resample2RC_c 1

foreign import ccall unsafe "resampleSSERC"
    resampleCSSERC_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCSSERC :: ResampleRC
resampleCSSERC = mkResamplerC resampleCSSERC_c 4

foreign import ccall unsafe "resampleAVXRC"
    resampleAVXRC_c :: CInt -> CInt -> CInt -> CInt -> Ptr CInt -> Ptr (Ptr CFloat) -> Ptr CFloat -> Ptr CFloat -> IO CInt

resampleCAVXRC :: ResampleRC
resampleCAVXRC = mkResamplerC resampleAVXRC_c 8

{-
 - Cross buffer
-}

{-# INLINE decimateCrossHighLevel #-}
decimateCrossHighLevel :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => Int -> v b -> Int -> v a -> v a -> vm (PrimState m) a -> m ()
decimateCrossHighLevel factor coeffs num lastBuf nextBuf outBuf = fill x outBuf
    where
    x = VFB.map dotProd (VFB.iterateN num (+ factor) 0)
    dotProd i = VG.sum $ VG.zipWith mult (VG.unsafeDrop i lastBuf VG.++ nextBuf) coeffs

{-# INLINE filterCrossHighLevel #-}
filterCrossHighLevel :: (PrimMonad m, Functor m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => v b -> Int -> v a -> v a -> vm (PrimState m) a -> m ()
filterCrossHighLevel coeffs num lastBuf nextBuf outBuf = fill (VFB.generate num dotProd) outBuf
    where
    dotProd i = VG.sum $ VG.zipWith mult (VG.unsafeDrop i lastBuf VG.++ nextBuf) coeffs

{-# INLINE resampleCrossHighLevel #-}
resampleCrossHighLevel :: (PrimMonad m, Num a, Mult a b, VG.Vector v a, VG.Vector v b, VGM.MVector vm a) => Int -> Int -> v b -> Int -> Int -> v a -> v a -> vm (PrimState m) a -> m Int
resampleCrossHighLevel interpolation decimation coeffs filterOffset count lastBuf nextBuf outBuf = fill 0 filterOffset 0
    where
    fill i filterOffset inputOffset
        | i < count = do
            let dp = dotProd filterOffset inputOffset
            VGM.unsafeWrite outBuf i dp
            let (q, r)        = divMod (decimation - filterOffset - 1) interpolation
                inputOffset'  = inputOffset + q + 1
                filterOffset' = interpolation - 1 - r
            filterOffset' `seq` inputOffset' `seq` fill (i + 1) filterOffset' inputOffset'
        | otherwise = return filterOffset
    dotProd filterOffset i = VG.sum $ VG.zipWith mult (VG.unsafeDrop i lastBuf VG.++ nextBuf) (stride interpolation (VG.unsafeDrop filterOffset coeffs))

foreign import ccall unsafe "dcBlocker"
    c_dcBlocker :: CInt -> CFloat -> CFloat -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> Ptr CFloat -> IO ()

dcBlocker :: Int -> Float -> Float -> VS.Vector Float -> VS.MVector RealWorld Float -> IO (Float, Float)
dcBlocker num lastSample lastOutput inBuf outBuf = 
    alloca $ \fsp -> 
        alloca $ \fop -> 
            VS.unsafeWith (VS.unsafeCoerceVector inBuf) $ \iPtr -> 
                VSM.unsafeWith (VSM.unsafeCoerceMVector outBuf) $ \oPtr -> do
                    c_dcBlocker (fromIntegral num) (realToFrac lastSample) (realToFrac lastOutput) fsp fop iPtr oPtr
                    r1 <- peek fsp
                    r2 <- peek fop
                    return (realToFrac r1, realToFrac r2)
