package util

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/distributed-lab/enclave-extras/attestedkms"
	"github.com/distributed-lab/enclave-extras/nitro"
	"github.com/distributed-lab/enclave-extras/nsm"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"

	"github.com/offchainlabs/nitro/cmd/genericconf"
)

type KMSAttestationConfig struct {
	attestationDoc []byte
	pk             *rsa.PrivateKey
}

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

// Prepare config for use with KMSEnclaveClient
func newKMSAttestationConfig() (*KMSAttestationConfig, error) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return nil, fmt.Errorf("failed to generate RSA private key: %w", err)
	}
	derEncodedPublicKey, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal public key PKIX: %w", err)
	}
	kmsAttestationDocRaw, err := nsm.GetAttestationDoc(nil, nil, derEncodedPublicKey)
	if err != nil {
		return nil, fmt.Errorf("failed to get attestation doc with public key: %w", err)
	}

	return &KMSAttestationConfig{
		attestationDoc: kmsAttestationDocRaw,
		pk:             privateKey,
	}, nil
}

func parsePKCS8ECPrivateKey(pcks8PrivateKey []byte) (*ecdsa.PrivateKey, error) {
	privateKeyAny, err := attestedkms.ParsePKCS8PrivateKey(pcks8PrivateKey)
	if err != nil {
		return nil, err
	}

	privateKey, ok := privateKeyAny.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("invalid EC private key")
	}

	return privateKey, nil
}

func defaultEnclaveKMSKeyPolicies(rootARN, principalARN string, pcrs map[string]string) string {
	defaultPolicy := map[string]interface{}{
		"Version": "2012-10-17",
		"Id":      "key-default-1",
		"Statement": []map[string]interface{}{
			{
				"Sid":    "Allow access for Key Administrators",
				"Effect": "Allow",
				"Principal": map[string]interface{}{
					"AWS": rootARN,
				},
				"Action": []string{
					"kms:CancelKeyDeletion",
					"kms:DescribeKey",
					"kms:DisableKey",
					"kms:EnableKey",
					"kms:GetKeyPolicy",
					"kms:ScheduleKeyDeletion",
				},
				"Resource": "*",
			},
			{
				"Sid":    "Enable enclave",
				"Effect": "Allow",
				"Principal": map[string]interface{}{
					"AWS": principalARN,
				},
				"Action": []string{
					"kms:Decrypt",
					"kms:GenerateRandom",
					"kms:GenerateDataKey",
					"kms:GenerateDataKeyPair",
				},
				"Resource": "*",
				"Condition": map[string]interface{}{
					"StringEqualsIgnoreCase": pcrs,
				},
			},
		},
	}

	// should never panic
	policy, _ := json.Marshal(defaultPolicy)
	return string(policy)
}

func safeStringDeref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// TODO: I don't know why, but golangci-lint raise warning,
// because it think that 'encoding/hex' is unused. Since warning
// don't allow to commit code, here is quick fix
func encodeToString(src []byte) string {
	return hex.EncodeToString(src)
}
