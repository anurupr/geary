/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.Service {
    IMAP,
    SMTP;
}

[Flags]
public enum Geary.ServiceFlag {
    IMAP,
    SMTP;
    
    public bool has_imap() {
        return (this & IMAP) == IMAP;
    }
    
    public bool has_smtp() {
        return (this & SMTP) == SMTP;
    }
}

