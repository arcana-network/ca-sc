library;

use ::data_structures::Request;

/// Logged when a deposit is made.
pub struct Deposit {
    /// The signer of the [Request].
    pub from: Address,
    /// The EIP-191 signed hash of the [Request].
    pub signed_message_hash: b256,
}

/// Logged when a request is filled.
pub struct Fill {
    /// The signer of the [Request].
    pub from: Address,
    /// The EIP-191 signed hash of the [Request].
    pub signed_message_hash: b256,
    /// The address that filled the [Request]
    pub solver: Address,
}

/// Logged when a withdraw is made.
pub struct Withdraw {
    /// The recipient of the withdrawal.
    pub to: Identity,
    /// The asset ID of the withdrawn asset.
    pub asset_id: AssetId,
    /// The amount to withdraw.
    pub amount: u64,
}

/// Logged when a settlement is made.
pub struct Settle {
    /// The address that filled a [Request].
    pub solver: Address,
    /// The asset ID of the asset to send the `solver`.
    pub asset_id: AssetId,
    /// The amount of the asset to send the `solver`.
    pub amount: u64,
    /// The nonce of the settlement.
    pub nonce: u256,
}

/// Logged when a `settlement verifier` role is set.
pub struct SettlementVerifierRoleSet {
    /// The `identity` who's status as a `settlement verifier` has been set.
    pub identity: Identity,
    /// The updated status.
    pub has_role: bool,
}

/// Logged when a `settlement verifier` role is transferred.
pub struct SettlementVerifierRoleTransfer {
    /// The `identity` who transferred the role.
    pub old_identity: Identity,
    /// The `identity` who received the role.
    pub new_identity: Identity,
}
/// Logged when a `refund eligible` role is set.
pub struct RefundEligibleRoleSet {
    /// The `identity` who's status as a `refund eligible` has been set.
    pub identity: Identity,
    /// The updated status.
    pub has_role: bool,
}

/// Logged when a `settlement verifier` role is transferred.
pub struct RefundEligibleRoleTransfer {
    /// The `identity` who transferred the role.
    pub old_identity: Identity,
    /// The `identity` who received the role.
    pub new_identity: Identity,
}
