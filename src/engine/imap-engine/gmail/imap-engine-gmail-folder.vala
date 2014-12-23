/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailFolder : MinimalFolder, FolderSupport.Archive,
    FolderSupport.Create {
    public GmailFolder(GmailAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public new async Geary.EmailIdentifier? create_email_async(
        RFC822.Message rfc822, Geary.EmailFlags? flags, DateTime? date_received,
        Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error {
        return yield base.create_email_async(rfc822, flags, date_received, id, cancellable);
    }
    
    public async Geary.Revokable? archive_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        // Use move_email_async("All Mail") here; Gmail will do the right thing and report
        // it was copied with the All Mail UID (in other words, no actual copy is performed).
        // This allows for undoing an archive with the same code path as a move.
        Geary.Folder? all_mail = account.get_special_folder(Geary.SpecialFolderType.ALL_MAIL);
        if (all_mail != null)
            return yield move_email_async(email_ids, all_mail.path, cancellable);
        
        // although this shouldn't happen, fall back on our traditional archive, which is simply
        // to remove the message from this label
        message("Unable to perform revokable archive on %s: All Mail not found", to_string());
        yield expunge_email_async(email_ids, cancellable);
        
        return null;
    }
}

