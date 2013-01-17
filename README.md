DreamHostPanelCLI
=================

Purpose
-------

An automatable command-line interface (CLI) interface for DreamHost's
custom Panel written in Perl.
 
License
-------

Copyright © 2013 Myq Larson
http://copyfree.org/licenses/gnu_all_permissive/license.txt


Road map
--------

* Enable bulk actions by creating a domain queue
* Navigate categories & actions by parsing left side bar
* Focus on reaching all forms and commands, even if the interface
  isn't pretty

Status
------

Incomplete. Can login, find domains and tasks, and forms on the Panel
pages for those tasks.

Currently looks like this:

    $ ./DreamHostPanelCLI.sh
    password:
    username: me@example.com

    Attempting to log in…
    loading options…
    1: billing
    2: dedicated
    3: domain
    4: ecommerce
    5: goodies
    6: home
    7: mail
    8: status
    9: storage
    10: support
    11: users
    12: vserver
    Which category?: 3

    1: ftp
    2: manage
    3: mapsubdir
    4: proxy
    5: registration
    6: secure
    7: transfer
    Which task?: 2

    $VAR1 = 'https://panel.dreamhost.com/index.cgi?tree=domain.manage&';
    $VAR1 = 'webftp_f_example_org';
    $VAR2 = 'a';
    $VAR3 = 'webftp_f_example_com';
    $VAR4 = 'webftp_f_example_info';
    $VAR5 = 'form0';
    $VAR6 = 'quicksearch_form';
    $VAR7 = '?tree=domain.manage&current_step=Index&next_step=ShowAddhttp&domain=';
    $VAR8 = '?tree=domain.manage&current_step=Index&next_step=ShowZone&domain=example.org';
    $VAR9 = '?tree=domain.manage&current_step=Index&next_step=ShowAddIP&domain=example.org';
    $VAR10 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyIP&domain=example.org&destroy_ip=2607:F298:0004:0148:0000:0000:xxxx:xxxx';
    $VAR11 = '?tree=domain.manage&current_step=Index&next_step=ShowEdithttp&dsid=20148192';
    $VAR12 = '?tree=domain.manage&current_step=Index&next_step=Deactivate&dsid=20148192&security_key=9f7907d0d1f36e8070652535bab1c29a';
    $VAR13 = '?tree=domain.secure&current_step=Index&next_step=Add&domain=example.org';
    $VAR14 = '?tree=mail.addresses&current_step=Index&next_step=DoSelector&domainselector=example.org&security_key=9f7907d0d1f36e8070652535bab1c29a';
    $VAR15 = '?tree=domain.manage&current_step=Index&next_step=ShowRestoreDomain&domain=example.org';
    $VAR16 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyDomain&domain=example.org';
    $VAR17 = '?tree=domain.manage&current_step=Index&next_step=ShowZone&domain=example.com';
    $VAR18 = '?tree=domain.manage&current_step=Index&next_step=ShowAddIP&domain=example.com';
    $VAR19 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyIP&domain=example.com&destroy_ip=2607:F298:0004:0148:0000:0000:xxxx:xxxx';
    $VAR20 = '?tree=domain.manage&current_step=Index&next_step=ShowEdithttp&dsid=19364852';
    $VAR21 = '?tree=domain.manage&current_step=Index&next_step=Deactivate&dsid=19364852&security_key=9f7907d0d1f36e8070652535bab1c29a';
    $VAR22 = '?tree=domain.secure&current_step=Index&next_step=Add&domain=example.com';
    $VAR23 = '?tree=domain.manage&current_step=Index&next_step=ShowRestoreDomain&domain=example.com';
    $VAR24 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyDomain&domain=example.com';
    $VAR25 = '?tree=domain.manage&current_step=Index&next_step=ShowZone&domain=example.info';
    $VAR26 = '?tree=domain.manage&current_step=Index&next_step=ShowAddIP&domain=example.info';
    $VAR27 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyIP&domain=example.info&destroy_ip=2607:F298:0004:0148:0000:0000:xxx:xxx';
    $VAR28 = '?tree=domain.manage&current_step=Index&next_step=ShowEdithttp&dsid=21816646';
    $VAR29 = '?tree=domain.manage&current_step=Index&next_step=Deactivate&dsid=21816646&security_key=9f7907d0d1f36e8070652535bab1c29a';
    $VAR30 = '?tree=domain.secure&current_step=Index&next_step=Add&domain=example.info';
    $VAR31 = '?tree=mail.addresses&current_step=Index&next_step=DoSelector&domainselector=example.info&security_key=9f7907d0d1f36e8070652535bab1c29a';
    $VAR32 = '?tree=domain.manage&current_step=Index&next_step=ShowDestroyDomain&domain=example.info';

The `$VARxx` lines are a dump of the froms and links found from the
_manage domains_ page.

Inputs for forms can be found with `getInputs()` function, or the
linked pages can be requested with `doGet()` and parsed for forms as
well. Labels for the above need to be added but for the most part they
are descriptive (_i.e._ Destroy IP, Add IP, Destroy Domain, Restore
Domain, etc). Some forms will need manual labels (_i.e. `form0`, `a`,
etc) but a descriptive label is usually an `<h1>` sibling element just
above the form which is easy to extract from the document tree in
`$currentPage`.

Most inputs in forms are self-descriptive as well.
