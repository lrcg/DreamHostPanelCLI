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


Warranty
--------

Ha! You're joking right? If you can't take responsibility for your own
self, then treat this script as 100% broken. Do not use!

Road map
--------

* Enable bulk actions by creating a domain queue
* Focus on reaching all forms and commands, even if the interface
  isn't pretty

Status
------

Works for some basic features under controlled circumstances. Still
buggy.

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
    Which category?: 1

    1: account
    2: accounts
    3: invoice
    4: payment
    5: secure
    Which task?: 2

    loading actions…
    1: close account/end all hosting
    2: rename account
    Which action?: 2
    
    loading form…
    Enter to accept current value: (My Account)
    new_name: My New Account Name

    submitting form…
    "My New Account Name" is the new name for this account! That ought to help you keep them all straight, The Happy DreamHost Account Renaming Robot!  
    Enter to accept current value: (y)
    Finished? (y/n): y


Inputs for forms can be found with `findInputs()` function, or the
linked pages can be requested with `doGet()` and parsed for forms as
well. Labels for the above need to be added but for the most part they
are descriptive (_i.e._ Destroy IP, Add IP, Destroy Domain, Restore
Domain, etc). Some forms will need manual labels (_i.e._ `form0`, `a`,
etc) but a descriptive label is usually an `<h1>` sibling element just
above the form which is easy to extract from the document tree in
`$currentPage`.

Most inputs in forms are self-descriptive as well.
