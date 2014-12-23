/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an operation with the Geary Engine that make be revoked (undone) at a later
 * time.
 */

public abstract class Geary.Revokable : BaseObject {
    public const string PROP_CAN_REVOKE = "can-revoke";
    public const string PROP_IS_REVOKING = "is-revoking";
    
    /**
     * Indicates if {@link revoke_async} is a valid operation for this {@link Revokable}.
     *
     * Due to later operations or notifications, it's possible for the Revokable to go invalid.
     * In some circumstances, this may be that it cannot fully revoke the original operation, in
     * others it may be that it can't revoke any part of the original operation, depending on the
     * nature of the operation.
     */
    public bool can_revoke { get; protected set; default = true; }
    
    /**
     * Indicates a {@link revoke_async} operation is underway.
     *
     * Only one revoke operation can occur at a time.  If this is true when revoke_async() is
     * called, it will throw an Error.
     */
    public bool is_revoking { get; protected set; default = false; }
    
    protected Revokable() {
    }
    
    /**
     * Revoke (undo) the operation.
     *
     * Returns false if the operation failed and is no longer revokable.
     *
     * If the call throws an Error that does not necessarily mean the {@link Revokable} is
     * invalid.  Check the return value or {@link can_revoke}.
     *
     * @throws EngineError.ALREADY_OPEN if {@link is_revoking} is true when called.
     */
    public abstract async bool revoke_async(Cancellable? cancellable = null) throws Error;
}

