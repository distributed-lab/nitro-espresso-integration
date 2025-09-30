package integrityattestation

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"os"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/distributed-lab/enclave-extras/nitro"

	"github.com/offchainlabs/nitro/util/signature"
)

func ReadEnclavePrivateKey(attestationsPath string) (*ecdsa.PrivateKey, signature.DataSignerFunc, error) {
	if err := os.MkdirAll(attestationsPath, os.ModePerm); err != nil {
		return nil, nil, fmt.Errorf("failed to create attestations path directory %s with error: %w", attestationsPath, err)
	}

	awsConfig, err := awsconfig.LoadDefaultConfig(context.Background())
	if err != nil {
		return nil, nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	kmsKeyID, err := nitro.GetAttestedKMSKeyID(awsConfig, attestationsPath)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get attested KMS Key ID: %w", err)
	}

	privateKey, err := nitro.GetAttestedPrivateKey(awsConfig, kmsKeyID, attestationsPath)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get attested private key: %w", err)
	}

	publicKey, err := nitro.GetAttestedPublicKey(privateKey, attestationsPath)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to get attested public key: %w", err)
	}

	if _, err = nitro.GetAttestedAddress(publicKey, attestationsPath); err != nil {
		return nil, nil, fmt.Errorf("failed to get attested address: %w", err)
	}

	return privateKey, signature.DataSignerFromPrivateKey(privateKey), nil
}
