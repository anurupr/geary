/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class CertificateWarningDialog {
    public enum Result {
        DONT_TRUST,
        TRUST,
        ALWAYS_TRUST
    }
    
    private const string BULLET = "&#8226; ";
    
    private Gtk.Dialog dialog;
    private Gtk.Label top_label;
    private Gtk.Label warnings_label;
    
    public CertificateWarningDialog(Gtk.Window? parent, Geary.Endpoint endpoint, TlsCertificateFlags warnings) {
        Gtk.Builder builder = GearyApplication.instance.create_builder("certificate_warning_dialog.glade");
        
        dialog = (Gtk.Dialog) builder.get_object("CertificateWarningDialog");
        top_label = (Gtk.Label) builder.get_object("top_label");
        warnings_label = (Gtk.Label) builder.get_object("warnings_label");
        
        dialog.transient_for = parent;
        dialog.modal = true;
        
        top_label.label = _("The identity of the mail server at %s:%u could not be verified:").printf(
            endpoint.remote_address.hostname, endpoint.remote_address.port);
        
        warnings_label.label = generate_warning_list(warnings);
        warnings_label.use_markup = true;
    }
    
    private static string generate_warning_list(TlsCertificateFlags warnings) {
        StringBuilder builder = new StringBuilder();
         
        if ((warnings & TlsCertificateFlags.UNKNOWN_CA) != 0)
            builder.append(BULLET + _("The server's certificate is not signed by a known authority") + "\n");
        
        if ((warnings & TlsCertificateFlags.BAD_IDENTITY) != 0)
            builder.append(BULLET + _("The server's identity does not match the identity in the certificate") + "\n");
        
        if ((warnings & TlsCertificateFlags.EXPIRED) != 0)
            builder.append(BULLET + _("The server's certificate has expired") + "\n");
        
        if ((warnings & TlsCertificateFlags.NOT_ACTIVATED) != 0)
            builder.append(BULLET + _("The server's certificate has not been activated") + "\n");
        
        if ((warnings & TlsCertificateFlags.REVOKED) != 0)
            builder.append(BULLET + _("The server's certificate has been revoked and is now invalid") + "\n");
        
        if ((warnings & TlsCertificateFlags.INSECURE) != 0)
            builder.append(BULLET + _("The server's certificate is considered insecure") + "\n");
        
        if ((warnings & TlsCertificateFlags.GENERIC_ERROR) != 0)
            builder.append(BULLET + _("An error has occurred processing the server's certificate") + "\n");
        
        return builder.str;
    }
    
    public Result run() {
        dialog.show_all();
        int response = dialog.run();
        dialog.destroy();
        
        // these values are defined in the Glade file
        switch (response) {
            case 1:
                return Result.TRUST;
            
            case 2:
                return Result.ALWAYS_TRUST;
            
            default:
                return Result.DONT_TRUST;
        }
    }
}

