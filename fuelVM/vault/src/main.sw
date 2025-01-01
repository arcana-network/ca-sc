contract;

mod interface;
pub mod data_structures;
mod events;
mod personal_sign_hash;
mod errors;

use interface::ArcanaVault;
use data_structures::{Request, SettleData, StorableRequest, SourcePair, DestinationPair};
use personal_sign_hash::personal_sign_hash;
use errors::VaultError;
use events::{Deposit, Fill, Settle, Withdraw};

use sway_libs::{ownership::{_owner, initialize_ownership, only_owner}, reentrancy::*};
use standards::src5::{SRC5, State};

use std::{
    asset::transfer,
    b512::B512,
    block::timestamp,
    call_frames::msg_asset_id,
    context::msg_amount,
    ecr::ec_recover_address,
    hash::{
        Hash,
        keccak256,
    },
    outputs::{
        output_amount,
        output_asset_id,
        output_asset_to,
        output_count,
    },
    storage::storage_vec::*
};

configurable {
    /// The Identity set as the `owner` during initialization.
    INITIAL_OWNER: Identity = Identity::Address(Address::zero()),
    /// The chain ID for Fuel Ignition.
    FUEL_IGNITION_CHAIN_ID: u256 = 9889,
}

storage {
    V1 {
        /// A mapping of `signed_message_hash` to `partial_request`.
        requests_partial: StorageMap<b256, StorableRequest> = StorageMap {},
        /// A mapping of `signed_message_hash` to `request_sources`.
        requests_sources: StorageMap<b256, StorageVec<SourcePair>> = StorageMap {},
        /// A mapping of `signed_message_hash` to `request_destinations`.
        requests_destinations: StorageMap<b256, StorageVec<DestinationPair>> = StorageMap {},
        /// A mapping of `deposit_nonce` to `bool`.
        deposit_nonce: StorageMap<u64, bool> = StorageMap {},
        /// A mapping of `fill_nonce` to `bool`.
        fill_nonce: StorageMap<u64, bool> = StorageMap {},
        /// A mapping of `settle_nonce` to `bool`.
        settle_nonce: StorageMap<u64, bool> = StorageMap {},
    },
}

impl SRC5 for Contract {
    /// Returns the owner.
    ///
    /// # Return Values
    ///
    /// * [State] - Represents the state of ownership for this contract.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    #[storage(read)]
    fn owner() -> State {
        _owner()
    }
}

impl ArcanaVault for Contract {
    /// Initializes the vault, setting privileged roles.
    ///
    /// # Additional Information
    ///
    /// This method can only be called once.
    ///
    /// # Reverts
    ///
    /// * When ownership has been set before.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    /// * Writes: `1`
    #[storage(read, write)]
    fn initialize_vault() {
        initialize_ownership(INITIAL_OWNER);
    }

    /// Takes a deposit for the given request.
    ///
    /// # Arguments
    ///
    /// * `request`: [Request] - The user's request.
    /// * `signature`: [B512] - The signature over the `request`.
    /// * `from`: [Address] - The signer of the `request`.
    /// * `chain_index`: [u64] - The index of the source data.
    ///
    /// This method verifies the given request against the given signature.
    ///
    /// # Reverts
    ///
    /// * When the `request` chain ID doesn't match `FUEL_IGNITION_CHAIN_ID`.
    /// * When the `request` has expired.
    /// * When the asset deposited doesn't match the asset in the `request`.
    /// * When the amount of asset deposited doesn't match the amount of asset in the `request`.
    /// * When the nonce of the `request` is already used.
    /// * When the `request` could not be verified.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3`
    /// * Writes: `4`
    #[payable]
    #[storage(read, write)]
    fn deposit(
        request: Request,
        signature: B512,
        from: Address,
        chain_index: u64,
    ) {
        require(
            (request
                    .sources
                    .get(chain_index)
                    .is_some()) && (request
                    .sources
                    .get(chain_index)
                    .unwrap()
                    .chain_id == FUEL_IGNITION_CHAIN_ID),
            VaultError::ChainIdMismatch,
        );

        require(request.expiry > timestamp(), VaultError::RequestExpired);

        require(
            msg_asset_id() == request
                .sources
                .get(chain_index)
                .unwrap()
                .asset_id,
            VaultError::AssetMismatch,
        );
        require(
            msg_amount() == request
                .sources
                .get(chain_index)
                .unwrap()
                .value,
            VaultError::ValueMismatch,
        );

        require(
            !storage::V1
                .deposit_nonce
                .get(request.nonce)
                .try_read()
                .unwrap_or(false),
            VaultError::NonceAlreadyUsed,
        );

        let request_hash = hash_request(request);

        let signed_message_hash = verify_request(signature, from, request_hash);

        storage::V1.deposit_nonce.insert(request.nonce, true);

        storage::V1.requests_partial.insert(signed_message_hash, request.into());
        storage::V1.requests_sources.get(signed_message_hash).store_vec(request.sources);
        storage::V1.requests_destinations.get(signed_message_hash).store_vec(request.destinations);

        log(Deposit {
            from,
            signed_message_hash,
        });
    }

    /// Verifies that a request has been filled.
    ///
    /// # Additional Information
    ///
    /// The solver calling this method must have included outputs in the transaction that satisfy the `request` destination data.
    ///
    /// * `request`: [Request] - The user's request.
    /// * `signature`: [B512] - The signature over the `request`.
    /// * `from`: [Address] - The signer of the `request`.
    ///
    /// # Reverts
    ///
    /// * When the `request` chain ID doesn't match `FUEL_IGNITION_CHAIN_ID`.
    /// * When the `request` has expired.
    /// * When the there aren't enough transaction outputs to satisfy the `request`.
    /// * When a transaction output doesn't match the corresponding destination pair or receiver.
    /// * When the nonce of the `request` is already used.
    /// * When the `request` could not be verified.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3`
    /// * Writes: `4`
    #[storage(read, write)]
    fn fill(request: Request, signature: B512, from: Address) {
        require(
            request
                .destination_chain_id == FUEL_IGNITION_CHAIN_ID,
            VaultError::ChainIdMismatch,
        );

        require(request.expiry > timestamp(), VaultError::RequestExpired);

        require(
            output_count()
                .as_u64() == request
                .destinations
                .len(),
            VaultError::InvalidFillOutputs,
        );
        
        let mut output_index = 0;
        for destination_pair in request.destinations.iter() {
            // Solver MUST include coin outputs that satisfy the destinations. 
            // Methods for variable outputs are unavailable atm so solver must take care to setup the ensure this method doesn't revert 
            // as they may still send the UTXOs.
            // Coin outputs MUST be ordered the same as the destination pairs.
            if destination_pair.value > 0 {
                let output_recipient = output_asset_to(output_index);
                require(
                    (output_recipient
                            .is_some()) && (output_recipient
                            .unwrap() == from),
                    VaultError::InvalidFillOutputs,
                );

                let output_asset_id = output_asset_id(output_index);
                require(
                    (output_asset_id
                            .is_some()) && (output_asset_id
                            .unwrap() == destination_pair
                            .asset_id),
                    VaultError::InvalidFillOutputs,
                );

                let output_amount = output_amount(output_index);
                require(
                    (output_amount
                            .is_some()) && (output_amount
                            .unwrap() == destination_pair
                            .value),
                    VaultError::InvalidFillOutputs,
                );
            }

            output_index = output_index + 1;
        }

        require(
            !storage::V1
                .fill_nonce
                .get(request.nonce)
                .try_read()
                .unwrap_or(false),
            VaultError::NonceAlreadyUsed,
        );

        let request_hash = hash_request(request);

        let signed_message_hash = verify_request(signature, from, request_hash);

        storage::V1.fill_nonce.insert(request.nonce, true);

        storage::V1.requests_partial.insert(signed_message_hash, request.into());
        storage::V1.requests_sources.get(signed_message_hash).store_vec(request.sources);
        storage::V1.requests_destinations.get(signed_message_hash).store_vec(request.destinations);

        log(Fill {
                from,
                signed_message_hash,
                solver: msg_sender().unwrap().as_address().unwrap(),
            });
        }

    /// Withdraw assets from the contract.
    ///
    /// # Additional Information
    ///
    /// Only callable by the contract owner.
    ///
    /// # Arguments
    ///
    /// * `to`: [Identity] - The recipient of the withdrawal.
    /// * `asset_id`: [AssetId] - The asset to withdraw.
    /// * `amount`: [u64] - The amount withdraw.
    ///
    /// # Reverts
    ///
    /// * When not called by the owner.
    /// * When reentrency occurs.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    #[storage(read)]
    fn withdraw(to: Identity, asset_id: AssetId, amount: u64) {
        only_owner();
        reentrancy_guard();

        transfer(to, asset_id, amount);

        log(Withdraw {
            to,
            asset_id,
            amount,
        });
    }

    /// Pay solvers for verified work.
    ///
    /// # Additional Information
    ///
    /// Anyone can call this method as it checks if the `settle_data` was signed by the contract owner, 
    /// if so the `settle_data` is considered valid.
    ///
    /// # Arguments
    ///
    /// * `settle_data`: [SettleData] - The data of each transfer to a solver.
    /// * `signature`: [B512] - The signature used to verify that the contract owner signed the given `settle_data`.
    ///
    /// # Reverts
    ///
    /// * When reentrency occurs.
    /// * When the number of solvers and assets in the `settle_data` don't match.
    /// * When the number of solvers and amounts in the `settle_data` don't match.
    /// * When the recovered address doesn't match the contract owner's address.
    /// * When the nonce of the `settle_data` is already used.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    /// * Writes: `1`
    #[storage(read, write)]
    fn settle(settle_data: SettleData, signature: B512) {
        reentrancy_guard();

        require(
            settle_data
                .solvers
                .len() == settle_data
                .assets
                .len(),
            VaultError::SolversAndAssetsLengthMismatch,
        );

        require(
            settle_data
                .solvers
                .len() == settle_data
                .amounts
                .len(),
            VaultError::SolversAndAmountsLengthMismatch,
        );

        let settle_data_hash = keccak256((settle_data, FUEL_IGNITION_CHAIN_ID));

        let signed_message_hash = personal_sign_hash(settle_data_hash);

        let recovered_address = ec_recover_address(signature, signed_message_hash).unwrap();

        require(
            State::Initialized(Identity::Address(recovered_address)) == _owner(),
            VaultError::InvalidSignature,
        );

        require(
            !storage::V1
                .settle_nonce
                .get(settle_data.nonce)
                .try_read()
                .unwrap_or(false),
            VaultError::NonceAlreadyUsed,
        );

        storage::V1.settle_nonce.insert(settle_data.nonce, true);

        let mut index = 0;
        while index < settle_data.solvers.len() {
            let solver = settle_data.solvers.get(index).unwrap();
            let asset_id = settle_data.assets.get(index).unwrap();
            let amount = settle_data.amounts.get(index).unwrap();

            transfer(Identity::Address(solver), asset_id, amount);

            log(Settle {
                solver,
                asset_id,
                amount,
                nonce: settle_data.nonce,
            });

            index = index + 1;
        }
    }

    /// Gets a [Request] hash from it's associated `signed_message_hash`
    ///
    /// # Arguments
    ///
    /// * `signed_message_hash`: [b256] - The hash of the EIP-191 signature of a hashed request.
    ///
    /// # Returns
    ///
    /// * [Option<Request>] - The request.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `3`
    #[storage(read)]
    fn requests(signed_message_hash: b256) -> Option<Request> {
        match storage::V1.requests_partial.get(signed_message_hash).try_read() {
            Option::Some(partial_request) => {
                let mut request: Request = partial_request.into();
                request.sources = storage::V1.requests_sources.get(signed_message_hash).load_vec();
                request.destinations = storage::V1.requests_destinations.get(signed_message_hash).load_vec();
                Some(request)
            },
            Option::None => None,
        }
    }

    /// Gets a bool describing whether a given nonce has been used in a deposit
    ///
    /// # Arguments
    ///
    /// * `nonce`: [u64] - The nonce of a deposit.
    ///
    /// # Returns
    ///
    /// * [Option<bool>] - Whether a given nonce has been used in a deposit.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    #[storage(read)]
    fn deposit_nonce(nonce: u64) -> Option<bool> {
        storage::V1.deposit_nonce.get(nonce).try_read()
    }

    /// Gets a bool describing whether a given nonce has been used in a fill
    ///
    /// # Arguments
    ///
    /// * `nonce`: [u64] - The nonce of a fill.
    ///
    /// # Returns
    ///
    /// * [Option<bool>] - Whether a given nonce has been used in a fill.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    #[storage(read)]
    fn fill_nonce(nonce: u64) -> Option<bool> {
        storage::V1.fill_nonce.get(nonce).try_read()
    }

    /// Gets a bool describing whether a given nonce has been used in a settlement
    ///
    /// # Arguments
    ///
    /// * `nonce`: [u64] - The nonce of a settlement.
    ///
    /// # Returns
    ///
    /// * [Option<bool>] - Whether a given nonce has been used in a settlement.
    ///
    /// # Number of Storage Accesses
    ///
    /// * Reads: `1`
    #[storage(read)]
    fn settle_nonce(nonce: u64) -> Option<bool> {
        storage::V1.settle_nonce.get(nonce).try_read()
    }
}

/// Get the keccak256 hash of a [Request]
///
///
/// # Arguments
///
/// * `request`: [Request] - The `request` to be hashed.
///
/// # Returns
///
/// * [b256] - The hash of the `request`.
fn hash_request(request: Request) -> b256 {
    keccak256(request)
}

/// Verifies if the EIP-191 signed hash of the given `request` was signed by `from`.
///
///
/// # Arguments
///
/// * `signature`: [B512] - The signature of `from` over the signed `request_hash`.
/// * `from`: [Address] - The signer.
/// * `request_hash`: [b256] - The hash of a [Request].
///
/// # Returns
///
/// * [b256] - The EIP-191 signed hash of the `request_hash`.
///
/// # Reverts
///
/// * When the recovered address doesn't match `from`.
fn verify_request(signature: B512, from: Address, request_hash: b256) -> b256 {
    let signed_message_hash = personal_sign_hash(request_hash);

    let recovered_address = ec_recover_address(signature, signed_message_hash).unwrap();

    require(recovered_address == from, VaultError::RequestUnverified);

    signed_message_hash
}
