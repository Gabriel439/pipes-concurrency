module Main ( main ) where

import Control.Concurrent hiding (yield)
import Control.Concurrent.Async
import Control.Concurrent.STM (atomically)
import Control.Monad (forever)
import Pipes
import Pipes.Concurrent
import qualified Pipes.Prelude as P
import System.Exit
import System.IO
import System.Timeout

defaultTimeout :: Int
defaultTimeout = 200000         -- 0.2 s

labelPrint :: (Show a) => String -> Consumer a IO r
labelPrint label = forever $ do
  a <- await
  lift $ putStrLn $ label ++ ": " ++ show a

testSenderClose :: Buffer Int -> IO ()
testSenderClose buffer = do
    (output, input, seal) <- spawn buffer
    t1 <- async $ do
        runEffect $ each [1..5] >-> toOutput output
        atomically seal
    t2 <- async $ do
        runEffect $   fromInput input
                  >-> P.chain (\_ -> threadDelay 1000)
                  >-> P.print
    wait t1
    wait t2

testSenderCloseDelayedSend :: Buffer Int -> IO ()
testSenderCloseDelayedSend buffer = do
    (output, input, seal) <- spawn buffer
    t1 <- async $ do
        runEffect $   each [1..5]
                  >-> P.tee (toOutput output)
                  >-> for cat (\_ -> lift $ threadDelay 2000)
        atomically seal
    t2 <- async $ do
        runEffect $   fromInput input
                  >-> P.chain (\_ -> threadDelay 1000)
                  >-> P.print
    wait t1
    wait t2

testReceiverClose :: Buffer Int -> IO ()
testReceiverClose buffer = do
    (output, input, seal) <- spawn buffer
    t1 <- async $ do
        runEffect $   each [1..]
                  >-> P.tee (toOutput output)
                  >-> P.chain (\_ -> threadDelay 1000)
                  >-> P.print
    t2 <- async $ do
        runEffect $ for (fromInput input >-> P.take 10) discard
        atomically seal
    wait t1
    wait t2

testReceiverCloseDelayedReceive :: Buffer Int -> IO ()
testReceiverCloseDelayedReceive buffer = do
    (output, input, seal) <- spawn buffer
    t1 <- async $ do
        runEffect $   each [1..]
                  >-> P.tee (toOutput output)
                  >-> P.chain (\_ -> threadDelay 1000)
                  >-> labelPrint "Send"
    t2 <- async $ do
        runEffect $   fromInput input
                  >-> P.take 10
                  >-> P.chain (\_ -> threadDelay 800)
                  >-> labelPrint "Recv"
        atomically seal
    wait t1
    wait t2

runTest :: IO () -> String -> IO ()
runTest test name = do
    putStrLn $ "Starting test: " ++ name
    hFlush stdout
    result <- timeout defaultTimeout test
    case result of
        Nothing -> do putStrLn $ "Test " ++ name ++ " timed out. Aborting."
                      exitFailure
        Just _  -> do putStrLn $ "Test " ++ name ++ " finished."
    hFlush stdout

runTestExpectTimeout :: IO () -> String -> IO ()
runTestExpectTimeout test name = do
    putStrLn $ "Starting test: " ++ name
    hFlush stdout
    result <- timeout defaultTimeout test
    case result of
        Nothing -> putStrLn $ "Test " ++ name ++ " timed out as expected."
        Just _  -> do
            putStrLn $
                   "Test "
                ++ name
                ++ " finished, but a timeout was expected. Aborting."
            exitFailure
    hFlush stdout

main :: IO ()
main = do
    runTest (testSenderClose unbounded) "UnboundedSenderClose"
    runTest (testSenderClose $ bounded 3) "BoundedFilledSenderClose"
    runTest (testSenderClose $ bounded 7) "BoundedNotFilledSenderClose"
    runTest (testSenderClose $ bounded 1) "SingleSenderClose"
    runTestExpectTimeout (testSenderCloseDelayedSend $ latest 42) "LatestSenderClose"
    runTest (testSenderCloseDelayedSend (newest 1)) "NewSenderClose"
    --
    runTest (testReceiverClose unbounded) "UnboundedReceiverClose"
    runTest (testReceiverClose $ bounded 3) "BoundedFilledReceiverClose"
    runTest (testReceiverClose $ bounded 7) "BoundedNotFilledReceiverClose"
    runTest (testReceiverClose $ bounded 1) "SingleReceiverClose"
    runTest (testReceiverCloseDelayedReceive $ latest 42) "LatestReceiverClose"
    runTest (testReceiverClose $ newest 1) "NewReceiverClose"
