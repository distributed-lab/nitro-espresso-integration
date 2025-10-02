package util

import (
	"context"
	"fmt"
	"math/big"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/distributed-lab/enclave-extras/nitro"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"

	"github.com/offchainlabs/nitro/cmd/genericconf"
)

const (
	awsConfigValidatorProfile = "validator"
	enclaveWalletSuffix       = ".enclave"
)

func OpenEnclaveValidatorWallet(description string, walletConfig *genericconf.WalletConfig, chainId *big.Int) (*bind.TransactOpts, error) {
	awsConfig, err := config.LoadDefaultConfig(context.Background(), config.WithSharedConfigProfile(awsConfigValidatorProfile))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS validator config: %w", err)
	}

	enclaveWalletPath := walletConfig.Pathname + enclaveWalletSuffix
	if err := os.MkdirAll(enclaveWalletPath, 0o700); err != nil {
		return nil, err
	}

	// Read or create KMS key
	kmsKeyID, err := nitro.GetAttestedKMSKeyID(awsConfig, enclaveWalletPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read or create KMS key: %w", err)
	}

	// Read or create Secp256k1 private key
	privateKey, err := nitro.GetAttestedPrivateKey(awsConfig, kmsKeyID, enclaveWalletPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read or create Secp256k1 private key: %w", err)
	}

	// Save public key if file does not exist
	_, err = nitro.GetAttestedPublicKey(privateKey, enclaveWalletPath)
	if err != nil {
		return nil, fmt.Errorf("failed to save public key: %w", err)
	}

	// Save address if file does not exist
	_, err = nitro.GetAttestedAddress(&privateKey.PublicKey, enclaveWalletPath)
	if err != nil {
		return nil, fmt.Errorf("failed to save address when file does not exist: %w", err)
	}

	if walletConfig.OnlyCreateKey {
		return nil, nil
	}

	txOpts, err := bind.NewKeyedTransactorWithChainID(privateKey, chainId)
	if err != nil {
		return nil, fmt.Errorf("failed to create keyed transactor: %w", err)
	}

	return txOpts, nil
}
