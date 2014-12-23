/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CopyEmail : Geary.ImapEngine.SendReplayOperation {
    public Gee.Set<Imap.UID>? destination_uids { get; private set; default = null; }
    
    private MinimalFolder engine;
    private Gee.HashSet<ImapDB.EmailIdentifier> to_copy = new Gee.HashSet<ImapDB.EmailIdentifier>();
    private Geary.FolderPath destination;
    private Cancellable? cancellable;

    public CopyEmail(MinimalFolder engine, Gee.List<ImapDB.EmailIdentifier> to_copy, 
        Geary.FolderPath destination, Cancellable? cancellable = null) {
        base("CopyEmail");
        
        this.engine = engine;
        
        this.to_copy.add_all(to_copy);
        this.destination = destination;
        this.cancellable = cancellable;
    }

    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
        to_copy.remove_all(ids);
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        if (to_copy.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        // The local DB will be updated when the remote folder is opened and we see a new message
        // existing there.
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        if (to_copy.size == 0)
            return ReplayOperation.Status.COMPLETED;
        
        Gee.Set<Imap.UID>? uids = yield engine.local_folder.get_uids_async(to_copy,
            ImapDB.Folder.ListFlags.NONE, cancellable);
        
        if (uids != null && uids.size > 0) {
            Gee.Set<Imap.UID> acc_uids = new Gee.HashSet<Imap.UID>();
            
            Gee.List<Imap.MessageSet> msg_sets = Imap.MessageSet.uid_sparse(uids);
            foreach (Imap.MessageSet msg_set in msg_sets) {
                Gee.Set<Imap.UID>? dest_uids = yield engine.remote_folder.copy_email_async(msg_set,
                    destination, cancellable);
                if (dest_uids != null)
                    acc_uids.add_all(dest_uids);
            }
            
            if (acc_uids.size > 0)
                destination_uids = acc_uids;
        }
        
        return ReplayOperation.Status.COMPLETED;
    }

    public override async void backout_local_async() throws Error {
        // Nothing to undo.
    }

    public override string describe_state() {
        return "%d email IDs to %s".printf(to_copy.size, destination.to_string());
    }
}

