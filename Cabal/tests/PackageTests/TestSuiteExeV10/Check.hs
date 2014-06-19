module PackageTests.TestSuiteExeV10.Check
       ( checkTest
       , checkTestWithHpc
       , checkTestWithoutHpcNoTix
       , checkTestWithoutHpcNoMarkup
       ) where

import Distribution.PackageDescription     ( TestSuite(..), emptyTestSuite )
import Distribution.Version                ( Version(..), orLaterVersion )
import Distribution.Simple.Hpc
import Distribution.Simple.Program.Builtin ( hpcProgram )
import Distribution.Simple.Program.Db      ( emptyProgramDb, configureProgram,
                                             requireProgramVersion )
import PackageTests.PackageTester
import Control.Exception                   ( bracket )
import qualified Control.Exception as E    ( IOException, catch )
import Control.Monad                       ( when )
import System.Directory                    ( doesFileExist )
import System.Environment                  ( getEnvironment )
-- Once we can depend on base >= 4.7.0.0 these can be imported from System.Environment
import System.SetEnv                       ( setEnv, unsetEnv )
import System.FilePath
import Test.HUnit

import qualified Distribution.Verbosity as Verbosity

dir :: FilePath
dir = "PackageTests" </> "TestSuiteExeV10"

checkTest :: FilePath -> Test
checkTest ghcPath = TestCase $ buildAndTest ghcPath []

-- | Ensure that both .tix file and markup are generated if coverage is enabled.
checkTestWithHpc :: FilePath -> Test
checkTestWithHpc ghcPath = TestCase $ do
    isCorrectVersion <- correctHpcVersion
    when isCorrectVersion $ do
      buildAndTest ghcPath ["--enable-library-coverage"]
      let dummy = emptyTestSuite { testName = "test-Foo" }
          tixFile = tixFilePath (dir </> "dist") $ testName dummy
          tixFileMessage = ".tix file should exist"
          markupDir = htmlDir (dir </> "dist") $ testName dummy
          markupFile = markupDir </> "hpc_index" <.> "html"
          markupFileMessage = "HPC markup file should exist"
      tixFileExists <- doesFileExist tixFile
      assertEqual tixFileMessage True tixFileExists
      markupFileExists <- doesFileExist markupFile
      assertEqual markupFileMessage True markupFileExists
  where

-- | Ensures that even if -fhpc is manually provided no .tix file is output.
checkTestWithoutHpcNoTix :: FilePath -> Test
checkTestWithoutHpcNoTix ghcPath = TestCase $ do
    isCorrectVersion <- correctHpcVersion
    when isCorrectVersion $ do
      buildAndTest ghcPath ["--ghc-option=-fhpc"]
      let dummy = emptyTestSuite { testName = "test-Foo" }
          tixFile = tixFilePath (dir </> "dist") $ testName dummy
          tixFileMessage = ".tix file should NOT exist"
      tixFileExists <- doesFileExist tixFile
      assertEqual tixFileMessage False tixFileExists

-- | Ensures that even if a .tix file happens to be left around
-- markup isn't generated.
checkTestWithoutHpcNoMarkup :: FilePath -> Test
checkTestWithoutHpcNoMarkup ghcPath = TestCase $ do
    isCorrectVersion <- correctHpcVersion
    when isCorrectVersion $ do
      let dummy = emptyTestSuite { testName = "test-Foo" }
          tixFile = tixFilePath "dist" $ testName dummy
          markupDir = htmlDir (dir </> "dist") $ testName dummy
          markupFile = markupDir </> "hpc_index" <.> "html"
          markupFileMessage = "HPC markup file should NOT exist"
      withEnv [("HPCTIXFILE", tixFile)] $ buildAndTest ghcPath ["--ghc-option=-fhpc"]
      markupFileExists <- doesFileExist markupFile
      assertEqual markupFileMessage False markupFileExists

-- | Build and test a package and ensure that both were successful.
--
-- The flag "--enable-tests" is provided in addition to the given flags.
buildAndTest :: FilePath -> [String] -> IO ()
buildAndTest ghcPath flags = do
    let spec = PackageSpec dir $ "--enable-tests" : flags
    buildResult <- cabal_build spec ghcPath
    assertBuildSucceeded buildResult
    testResult <- cabal_test spec [] ghcPath
    assertTestSucceeded testResult

-- | Perform an IO action with the given set of environment variable settings.
withEnv :: [(String, String)] -> IO a -> IO a
withEnv env = bracket applyAndBackup (mapM_ $ uncurry restoreEnv) . const
  where
    applyAndBackup = do
        environment <- getEnvironment
        let currentSettings = map (flip lookup environment . fst) env
        mapM_ (uncurry setEnv) env
        return $ zip (map fst env) currentSettings
    restoreEnv name Nothing = unsetEnv name
    restoreEnv name (Just value) = setEnv name value

-- | Checks for a suitable HPC version for testing.
correctHpcVersion :: IO Bool
correctHpcVersion = do
    let programDb' = emptyProgramDb
    let verbosity = Verbosity.normal
    let verRange  = orLaterVersion (Version [0,7] [])
    programDb <- configureProgram verbosity hpcProgram programDb'
    (requireProgramVersion verbosity hpcProgram verRange programDb
     >> return True) `catchIO` (\_ -> return False)
  where
    -- Distribution.Compat.Exception is hidden.
    catchIO :: IO a -> (E.IOException -> IO a) -> IO a
    catchIO = E.catch

