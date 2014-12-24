/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.PredictInsertOperation : ConversationOperation {
    private Gee.Collection<Geary.EmailIdentifier> predicted_ids;
    
    public PredictInsertOperation(ConversationMonitor monitor,
        Gee.Collection<Geary.EmailIdentifier> predicted_ids) {
        base(monitor);
        this.predicted_ids = predicted_ids;
    }
    
    public override async void execute_async() {
        yield monitor.predict_emails_async(predicted_ids);
    }
}
