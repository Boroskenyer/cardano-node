{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module Cardano.Config.Parsers
  ( command'
  , nodeCLIParser
  , parseConfigFile
  , parseCoreNodeId
  , parseDbPath
  , parseFilePath
  , parseLovelace
  , parseUrl
  , parseFlag
  , parseFlag'
  , parseFraction
  , parseGenesisFile
  , parseIntegral
  , parseIntegralWithDefault
  , parseLogOutputFile
  , parseNodeAddress
  , parseNodeId
  , parseSigningKeyFile
  , parseSocketPath
  , readDouble
  ) where


import           Prelude (String)

import           Cardano.Prelude hiding (option)

import           Cardano.Chain.Common (Lovelace, mkLovelace)
import           Cardano.Config.Byron.Parsers   as Byron
import           Cardano.Config.Shelley.Parsers as Shelley
import           Cardano.Config.Topology
import           Cardano.Config.Types


import           Network.Socket (PortNumber)
import           Options.Applicative

import           Ouroboros.Consensus.NodeId (NodeId(..), CoreNodeId(..))
import           Ouroboros.Network.Block (MaxSlotNo(..), SlotNo(..))


-- Common command line parsers

command' :: String -> String -> Parser a -> Mod CommandFields a
command' c descr p =
    command c $ info (p <**> helper)
              $ mconcat [ progDesc descr ]

nodeCLIParser  :: Parser NodeCLI
nodeCLIParser = nodeRealProtocolModeParser <|> nodeMockProtocolModeParser

nodeMockProtocolModeParser :: Parser NodeCLI
nodeMockProtocolModeParser = subparser
                           (  commandGroup "Execute node with a mock protocol."
                           <> metavar "run-mock"
                           <> command "run-mock"
                                (info (nodeMockParser <**> helper)
                                      (progDesc "Execute node with a mock protocol."))
                           )
nodeRealProtocolModeParser :: Parser NodeCLI
nodeRealProtocolModeParser = subparser
                           (  commandGroup "Execute node with a real protocol."
                           <> metavar "run"
                           <> command "run"
                                (info (nodeRealParser <**> helper)
                                      (progDesc "Execute node with a real protocol." ))
                           )

-- | The mock protocol parser.
nodeMockParser :: Parser NodeCLI
nodeMockParser = do
  -- Filepaths
  topFp <- parseTopologyFile
  dbFp <- parseDbPath
  socketFp <- optional $ parseSocketPath "Path to a cardano-node socket"

  -- NodeConfiguration filepath
  nodeConfigFp <- parseConfigFile

  -- Node Address
  nAddress <- optional parseNodeAddress

  validate <- parseValidateDB
  shutdownIPC <- parseShutdownIPC
  shutdownOnSlotSynced <- parseShutdownOnSlotSynced

  pure $ NodeCLI
           { nodeMode = MockProtocolMode
           , nodeAddr = nAddress
           , configFile   = ConfigYamlFilePath nodeConfigFp
           , topologyFile = TopologyFile topFp
           , databaseFile = DbFile dbFp
           , socketFile   = socketFp
           , protocolFiles = ProtocolFilepaths
             { byronCertFile = Nothing
             , byronKeyFile  = Nothing
             , shelleyKESFile  = Nothing
             , shelleyVRFFile  = Nothing
             , shelleyCertFile = Nothing
             }
           , validateDB = validate
           , shutdownIPC
           , shutdownOnSlotSynced
           }

-- | The real protocol parser.
nodeRealParser :: Parser NodeCLI
nodeRealParser = do
  -- Filepaths
  topFp <- parseTopologyFile
  dbFp <- parseDbPath
  socketFp <-   optional $ parseSocketPath "Path to a cardano-node socket"

  -- Protocol files
  byronCertFile   <- optional Byron.parseDelegationCert
  byronKeyFile    <- optional Byron.parseSigningKey
  shelleyKESFile  <- optional Shelley.parseKesKeyFilePath
  shelleyVRFFile  <- optional Shelley.parseVrfKeyFilePath
  shelleyCertFile <- optional Shelley.parseOperationalCertFilePath

  -- Node Address
  nAddress <- optional parseNodeAddress

  -- NodeConfiguration filepath
  nodeConfigFp <- parseConfigFile

  validate <- parseValidateDB
  shutdownIPC <- parseShutdownIPC

  shutdownOnSlotSynced <- parseShutdownOnSlotSynced

  pure NodeCLI
    { nodeMode = RealProtocolMode
    , nodeAddr = nAddress
    , configFile   = ConfigYamlFilePath nodeConfigFp
    , topologyFile = TopologyFile topFp
    , databaseFile = DbFile dbFp
    , socketFile   = socketFp
    , protocolFiles = ProtocolFilepaths
      { byronCertFile
      , byronKeyFile
      , shelleyKESFile
      , shelleyVRFFile
      , shelleyCertFile
      }
    , validateDB = validate
    , shutdownIPC
    , shutdownOnSlotSynced
    }

parseConfigFile :: Parser FilePath
parseConfigFile =
  strOption
    ( long "config"
    <> metavar "NODE-CONFIGURATION"
    <> help "Configuration file for the cardano-node"
    <> completer (bashCompleter "file")
    )

parseDbPath :: Parser FilePath
parseDbPath =
  strOption
    ( long "database-path"
    <> metavar "FILEPATH"
    <> help "Directory where the state is stored."
    )


parseGenesisFile :: String -> Parser GenesisFile
parseGenesisFile opt =
  GenesisFile <$> parseFilePath opt "Genesis JSON file."

-- Common command line parsers

parseFilePath :: String -> String -> Parser FilePath
parseFilePath optname desc =
  strOption $ long optname <> metavar "FILEPATH" <> help desc

parseFraction :: String -> String -> Parser Rational
parseFraction optname desc =
  option (toRational <$> readDouble) $
      long optname
   <> metavar "DOUBLE"
   <> help desc

parseLovelace :: String -> String -> Parser Lovelace
parseLovelace optname desc =
  either (panic . show) identity . mkLovelace
    <$> parseIntegral optname desc

parseUrl :: String -> String -> Parser String
parseUrl optname desc =
  strOption $ long optname <> metavar "URL" <> help desc

parseIntegral :: Integral a => String -> String -> Parser a
parseIntegral optname desc = option (fromInteger <$> auto)
  $ long optname <> metavar "INT" <> help desc

parseIntegralWithDefault :: Integral a => String -> String -> a -> Parser a
parseIntegralWithDefault optname desc def = option (fromInteger <$> auto)
 $ long optname <> metavar "INT" <> help desc <> value def

parseFlag :: String -> String -> Parser Bool
parseFlag = parseFlag' False True

parseFlag' :: a -> a -> String -> String -> Parser a
parseFlag' def active optname desc =
  flag def active $ long optname <> help desc

parseCoreNodeId :: Parser CoreNodeId
parseCoreNodeId =
    option (fmap CoreNodeId auto) (
            long "core-node-id"
         <> metavar "CORE-NODE-ID"
         <> help "The ID of the core node to which this client is connected."
    )

parseNodeId :: String -> Parser NodeId
parseNodeId desc =
    option (fmap (CoreId . CoreNodeId) auto) (
            long "node-id"
         <> metavar "NODE-ID"
         <> help desc
    )

parseNodeAddress :: Parser NodeAddress
parseNodeAddress = NodeAddress <$> parseHostAddr <*> parsePort

parseHostAddr :: Parser NodeHostAddress
parseHostAddr =
    option (eitherReader parseNodeHostAddress) (
          long "host-addr"
       <> metavar "HOST-NAME"
       <> help "Optionally limit node to one ipv6 or ipv4 address"
       <> value (NodeHostAddress Nothing)
    )

parsePort :: Parser PortNumber
parsePort =
    option ((fromIntegral :: Int -> PortNumber) <$> auto) (
          long "port"
       <> metavar "PORT"
       <> help "The port number"
       <> value 0 -- Use an ephemeral port
    )

parseValidateDB :: Parser Bool
parseValidateDB =
    switch (
         long "validate-db"
      <> help "Validate all on-disk database files"
    )

parseShutdownIPC :: Parser (Maybe Fd)
parseShutdownIPC =
    optional $ option (Fd <$> auto) (
         long "shutdown-ipc"
      <> metavar "FD"
      <> help "Shut down the process when this inherited FD reaches EOF"
      <> hidden
    )

parseShutdownOnSlotSynced :: Parser MaxSlotNo
parseShutdownOnSlotSynced =
    fmap (fromMaybe NoMaxSlotNo) $
    optional $ option (MaxSlotNo . SlotNo <$> auto) (
         long "shutdown-on-slot-synced"
      <> metavar "SLOT"
      <> help "Shut down the process after ChainDB is synced up to the specified slot"
      <> hidden
    )

parseSigningKeyFile :: String -> String -> Parser SigningKeyFile
parseSigningKeyFile opt desc = SigningKeyFile <$> parseFilePath opt desc

parseSocketPath :: Text -> Parser SocketPath
parseSocketPath helpMessage =
  SocketPath <$> strOption
    ( long "socket-path"
        <> (help $ toS helpMessage)
        <> completer (bashCompleter "file")
        <> metavar "FILEPATH"
    )

parseTopologyFile :: Parser FilePath
parseTopologyFile =
    strOption (
            long "topology"
         <> metavar "FILEPATH"
         <> help "The path to a file describing the topology."
    )

parseLogOutputFile :: Parser FilePath
parseLogOutputFile =
  strOption
    ( long "log-output"
    <> metavar "FILEPATH"
    <> help "Logging output file"
    <> completer (bashCompleter "file")
    )

readDouble :: ReadM Double
readDouble = do
  f <- auto
  when (f < 0) $ readerError "fraction must be >= 0"
  when (f > 1) $ readerError "fraction must be <= 1"
  return f
