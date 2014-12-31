/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.RevokableMove : Revokable {
    private GenericAccount account;
    private FolderPath original_source;
    private FolderPath original_dest;
    private Gee.Set<ImapDB.EmailIdentifier> destination_ids;
    
    /**
     * Supplied EmailIdentifiers *must* be loaded with UIDs of the messages on the *destination*
     * folder.  Do *not* merely stuff in here the EmailIdentifier from the source folder.
     */
    public RevokableMove(GenericAccount account, FolderPath original_source, FolderPath original_dest,
        Gee.Set<ImapDB.EmailIdentifier> destination_ids) {
        this.account = account;
        this.original_source = original_source;
        this.original_dest = original_dest;
        this.destination_ids = destination_ids;
        
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.email_removed.connect(on_folder_email_removed);
    }
    
    ~RevokableMove() {
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.email_removed.disconnect(on_folder_email_removed);
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
        MinimalFolder? dest_folder = null;
        try {
            Geary.Folder folder = yield account.fetch_folder_async(original_dest, cancellable);
            dest_folder = folder as ImapEngine.MinimalFolder;
        } catch (Error err) {
            debug("Unable to revoke move to %s: %s", original_dest.to_string(), err.message);
        }
        
        if (dest_folder == null)
            return can_revoke = false;
        
        // open, revoke, close, ensuring the close and signal disconnect are performed in all cases
        try {
            yield dest_folder.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
            
            // watch out for messages detected as gone when folder is opened
            if (can_revoke) {
                yield dest_folder.revoke_move_async(destination_ids, original_source, cancellable);
                can_revoke = false;
                
                // there's not a super-reliable way to wait until the delete of the message in this
                // folder has completed; could wait for the UID to be reported deleted, but it's
                // possible in IMAP to delete a message not present in folder and not get an error
                // (but also not be notified of its removal), and so waiting is a bad idea.  Don't
                // want to close the folder immediately because that leaves the local remove_marker
                // in place and the folder is treated as "dirty", causing a full renormalize to
                // occur when next opened, which is expensive.  So: just wait a bit and give the
                // server a chance to report the message is gone, leaving the db in a good state.
                // Do this *after* marking can_revoke=false so client is notified that this object
                // is now worthless.
                yield Scheduler.sleep_async(5);
            }
        } finally {
            // note that the Cancellable is not used
            try {
                yield dest_folder.close_async();
            } catch (Error err) {
                // ignored
            }
        }
        
        return can_revoke;
    }
    
    private void on_folders_available_unavailable(Gee.List<Folder>? available, Gee.List<Folder>? unavailable) {
        // look for either of the original folders going away
        if (unavailable != null) {
            foreach (Folder folder in unavailable) {
                if (folder.path.equal_to(original_source) || folder.path.equal_to(original_dest)) {
                    can_revoke = false;
                    
                    break;
                }
            }
        }
    }
    
    private void on_folder_email_removed(Folder folder, Gee.Collection<EmailIdentifier> ids) {
        // watch for destination folder's UIDs being removed
        if (!folder.path.equal_to(original_dest))
            return;
        
        // one-way switch
        if (!can_revoke)
            return;
        
        // convert generic identifiers to UIDs
        Gee.HashSet<Imap.UID> removed_uids = traverse<EmailIdentifier>(ids)
            .cast_object<ImapDB.EmailIdentifier>()
            .filter(id => id.uid == null)
            .map<Imap.UID>(id => id.uid)
            .to_hash_set();
        
        // otherwise, ability to revoke is best-effort
        Gee.Iterator<ImapDB.EmailIdentifier> iter = destination_ids.iterator();
        while (iter.next()) {
            if (removed_uids.contains(iter.get().uid))
                iter.remove();
        }
        
        can_revoke = destination_ids.size > 0;
    }
}

