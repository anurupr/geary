/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.RevokableMove : Revokable {
    private Account account;
    private FolderPath original_source;
    private FolderPath original_dest;
    private Gee.Set<Imap.UID> uids;
    private MinimalFolder? dest_folder = null;
    
    public RevokableMove(Account account, FolderPath original_source, FolderPath original_dest,
        Gee.Set<Imap.UID> uids) {
        this.account = account;
        this.original_source = original_source;
        this.original_dest = original_dest;
        this.uids = uids;
    }
    
    public override async bool revoke_async(Cancellable? cancellable) throws Error {
        if (is_revoking)
            throw new EngineError.ALREADY_OPEN("Already revoking operation");
        
        is_revoking = true;
        try {
            return yield internal_revoke_async(cancellable);
        } finally {
            is_revoking = false;
        }
    }
    
    private async bool internal_revoke_async(Cancellable? cancellable) throws Error {
        // moving from original destination to original source
        try {
            Geary.Folder folder = yield account.fetch_folder_async(original_dest, cancellable);
            dest_folder = folder as ImapEngine.MinimalFolder;
        } catch (Error err) {
            debug("Unable to revoke move to %s: %s", original_dest.to_string(), err.message);
        }
        
        if (dest_folder == null)
            return can_revoke = false;
        
        // trap removal of the UIDs we're moving
        dest_folder.uids_removed.connect(on_folder_uids_removed);
        
        // open, revoke, close, ensuring the close and signal disconnect are performed in all cases
        try {
            yield dest_folder.open_async(Geary.Folder.OpenFlags.NO_DELAY, cancellable);
            
            if (!yield dest_folder.revoke_move_async(uids, original_source, cancellable))
                can_revoke = false;
        } finally {
            // note that the Cancellable is not used
            try {
                yield dest_folder.close_async();
            } catch (Error err) {
                // ignored
            }
            
            dest_folder.uids_removed.disconnect(on_folder_uids_removed);
            dest_folder = null;
        }
        
        return can_revoke;
    }
    
    private void on_folder_uids_removed(Gee.Collection<Imap.UID> removed_uids) {
        // one-way switch
        if (!can_revoke)
            return;
        
        // otherwise, ability to revoke is best-effort
        uids.remove_all(removed_uids);
        can_revoke = uids.size > 0;
    }
}

