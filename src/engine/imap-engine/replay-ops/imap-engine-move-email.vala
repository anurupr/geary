/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.MoveEmail : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<ImapDB.EmailIdentifier>? destination_ids { get; private set; default = null; }
    
    private MinimalFolder engine;
    private Gee.List<ImapDB.EmailIdentifier> to_move = new Gee.ArrayList<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;
    private Gee.Set<ImapDB.EmailIdentifier>? moved_ids = null;
    private Gee.Set<ImapDB.EmailIdentifier>? predicted_ids = null;
    private int original_count = 0;

    public MoveEmail(MinimalFolder engine, Gee.List<ImapDB.EmailIdentifier> to_move, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("MoveEmail");

        this.engine = engine;

        this.to_move.add_all(to_move);
        this.destination = destination;
        this.cancellable = cancellable;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        // don't bother updating on server or backing out locally
        if (moved_ids != null)
            moved_ids.remove_all(ids);
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_move.size <= 0)
            return ReplayOperation.Status.COMPLETED;
        
        int remote_count;
        int last_seen_remote_count;
        original_count = engine.get_remote_counts(out remote_count, out last_seen_remote_count);
        
        // as this value is only used for reporting, offer best-possible service
        if (original_count < 0)
            original_count = to_move.size;
        
        moved_ids = yield engine.local_folder.mark_removed_async(to_move, true, cancellable);
        if (moved_ids == null || moved_ids.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        engine.notify_email_removed(moved_ids);
        
        engine.notify_email_count_changed(Numeric.int_floor(original_count - moved_ids.size, 0),
            Geary.Folder.CountChangeReason.REMOVED);
        
        // Report to the local destination Folder that new messages are predicted to arrive
        MinimalFolder? dest_folder = (yield engine.account.fetch_folder_async(destination, cancellable))
            as MinimalFolder;
        if (dest_folder != null) {
            // convert moved identifiers to prediction identifiers, which have no UID (that comes
            // after the network portion of the operation finishes) ... this allows for open folders
            // to report new mail without waiting for the operation to finish
            predicted_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
            foreach (ImapDB.EmailIdentifier moved_id in moved_ids)
                predicted_ids.add(new ImapDB.EmailIdentifier(moved_id.message_id, null));
            
            dest_folder.notify_predict_email_inserted(predicted_ids);
        }
        
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        if (moved_ids != null)
            ids.add_all(moved_ids);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (moved_ids.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // don't use Cancellable throughout I/O operations in order to assure transaction completes
        // fully
        if (cancellable != null && cancellable.is_cancelled())
            throw new IOError.CANCELLED("Move email to %s cancelled", engine.remote_folder.to_string());
        
        // Use this accumulator through the iteration of message set(s) and then store it all at
        // once in destination_ids
        Gee.Set<ImapDB.EmailIdentifier> acc_ids = new Gee.HashSet<ImapDB.EmailIdentifier>();
        
        // Create a map of UIDs to moved_ids to make lookup easy when generating destination ids
        Gee.Map<Imap.UID, ImapDB.EmailIdentifier> source_uid_to_source_id =
            traverse<ImapDB.EmailIdentifier>(moved_ids)
                .to_hash_map<Imap.UID>(id => id.uid);
        
        Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(
            ImapDB.EmailIdentifier.to_uids(moved_ids));
        foreach (Imap.MessageSet msg_set in msg_sets) {
            Gee.Map<Imap.UID, Imap.UID>? copyuids = yield engine.remote_folder.copy_email_async(msg_set,
                destination, null);
            yield engine.remote_folder.remove_email_async(msg_set, null);
            
            // convert returned COPYUID response into EmailIdentifiers for the destination folder
            if (copyuids != null && copyuids.size > 0) {
                Gee.MapIterator<Imap.UID, Imap.UID> iter = copyuids.map_iterator();
                while (iter.next()) {
                    Imap.UID source_uid = iter.get_key();
                    if (source_uid_to_source_id.has_key(source_uid)) {
                        ImapDB.EmailIdentifier source_id = source_uid_to_source_id[source_uid];
                        
                        acc_ids.add(new ImapDB.EmailIdentifier(source_id.message_id, iter.get_value()));
                    }
                }
            }
        }
        
        if (acc_ids.size > 0) {
            // link the destination id's to the local folder, which saves a little trouble when
            // normalizing with the remote as well as makes revoking them work properly
            MinimalFolder? dest_folder = (yield engine.account.fetch_folder_async(destination))
                as MinimalFolder;
            if (dest_folder != null) {
                try {
                    // Note that this doesn't require dest_folder be open because we're going straight
                    // to the database...dest_folder will announce to its subscribers changes when
                    // normalization/notification occurs via IMAP
                    yield dest_folder.local_folder.link_multiple_emails_async(acc_ids, null);
                    destination_ids = acc_ids;
                } catch (Error err) {
                    debug("Unable to link moved emails to new folder: %s", err.message);
                }
            }
        }
        
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        yield engine.local_folder.mark_removed_async(moved_ids, false, cancellable);
        
        engine.notify_email_inserted(moved_ids);
        engine.notify_email_count_changed(original_count, Geary.Folder.CountChangeReason.INSERTED);
        
        if (!Collection.is_empty(predicted_ids)) {
            MinimalFolder? dest_folder = (yield engine.account.fetch_folder_async(destination, cancellable))
                as MinimalFolder;
            if (dest_folder != null)
                dest_folder.notify_unpredict_email_inserted(predicted_ids);
        }
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_move.size, destination.to_string());
    }
}

