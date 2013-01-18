#!/usr/bin/env perl 

# Purpose: An automatable CLI interface to DH's Panel

# Status: Incomplete. Can login, find domains and tasks, and forms on
# the Panel pages for those tasks.

# Copyright © 2013 Myq Larson
# http://copyfree.org/licenses/gnu_all_permissive/license.txt

use strict;
use warnings;
use v5.10;
use feature 'say';

# LWP - The World-Wide Web library for Perl
# used for GETting and POSTing
use LWP::UserAgent;
# Browser created by th above
my $ua;

# Used to parse HTML documents and filter by tag & attributes
use HTML::TreeBuilder;
# Instantiate parser
my $tree = HTML::TreeBuilder->new();

# Cookies storage abject
use HTTP::Cookies;
my $cookie_jar = HTTP::Cookies->new(
    file     => "$ENV{'HOME'}/.dhp_cli_cookies.dat",
    autosave => 1
);

# Pure Perl JSON to deal with non-standard JSON
use JSON::PP; 

# For development
use Data::Dumper;

# Fro reading user input
use Term::ReadKey;

# Globals to the script

# DH's panel
my $baseURL  = 'https://panel.dreamhost.com/';

# Keep track of login status to avoid authenticating more than once
my $LoggedIn = 0;

# parsed DOM
my $currentPage;

# Selected task value from %task_categories
my $currentTaskTree;
# URL to request page for current task
my $currentTaskUrl;

my $currentActionText;
my $currentActionUrl;

# Hash of domains known to DH panel
my %domains;

# Hash of possible tasks to perform
my %tasks;

# Hash of available tasks derived from links in left column as
# category->subcategory = tree parameter of URL
# ex: https://panel.dreamhost.com/index.cgi?tree=billing.invoice& 
# becomes: $task_categories{'billing'}{'invoice'} = 'billing.invoice'
my %task_categories;

# Hash of task links extracted from main Panel 
my %task_links;

# Hash of forms available on $currentPage for completion
# my %forms;

# array of sorted options to display for user selection
my @options;

# Setup browser
# Returns nothing
sub initBrowser {
    $ua = LWP::UserAgent->new;
    $ua->agent( "DHAutomater/0.1 " );
    $ua->cookie_jar( $cookie_jar );
}

# Dump vars and exit (for development)
# Some hashes don't seem to work unless passed as {%hash}
# @param mixed var to dump
# @param bool  optional switch to continue processing rather than exit
sub d {
    my ( $var, $finished ) = @_;
    $finished = 1 unless defined $finished;
    print Dumper $var ;
    if ( $finished ) {
        exit;
    }
}

# Parse document and make it available to all
sub setCurrentPage {
    my $document = shift;
    $currentPage = $tree->parse_content( $document );
}

# POST data in %form to $url
# @todo return false on failure
sub doPost {
    my ( $url, %form ) = @_;

    my $res = $ua->post( $url, \%form );
    # &setCurrentPage( $res->content );
    return $res;
}

# GET $url
# @todo return false on failure
sub doGet {
    my ( $url ) = @_;

    my $res = $ua->get( $url );
    # &setCurrentPage( $res->content );
    return $res;

    # my $res = $ua->request( @_ );
    # if ( $res->is_success ) { return $res; } else { return 0; }
}

# Return array of HTML::Elements in global $currentPage for a given
# tag and optionally matching attributes using HTML::look_down() with
# attributes defined in %attrFilter
sub findElements {
    my ( $el, %attrFilter ) = @_;
    my @elements;

    if ( !%attrFilter ) {
        @elements = $currentPage->find_by_tag_name( $el );
    } else {
        $attrFilter{'_tag'} = $el;
        @elements = $currentPage->look_down( %attrFilter );
    }
    return ( @elements );
}

# Find all available forms in $currentPage, basically a specific form
# of findElements()

#  Forms for actions seem to always have the class `fancyform` so this
# can be used as a filter

# @todo why are forms from previous pages staying in memory???
sub findForms {
    my $fancyforms_only = shift || 0;

    my %attrs;
    %attrs = ( class => 'fancyform' ) if $fancyforms_only;

    my ( @forms ) = &findElements( 'form', %attrs );
    my %forms;
    my $form_name;
    my $i = 0;
    foreach my $form ( @forms ) {
        $form_name = $form->attr( 'name' ) || $form->attr( 'id' ) || 'form' . $i++;

        if ( $form_name ) {
            # say $form_name;
            $forms{$form_name} = $form;
        }
    }
    return ( %forms );
}

# Finds all inputs of a $form object from findForms(), technically a
# DOM fragment returns a hash of (name => value) attributes for each
# input @todo still need to find other forms of input such as
# `<select>` and `<textarea>` and `<button>`
sub findInputs {
    my ( $form ) = @_;
    # %inputs = hash of name => values extracted from @inputs
    my %inputs = ( hidden => {}, visible => {} );
    # @inputs = array of HTML::Elements
    my @inputs = $form->find_by_tag_name( 'input' );
    my $i = 0;
    foreach my $input ( @inputs ) {
        # ignore submit buttons
        my $type = $input->attr( 'type' ) || 0;
        next if $type eq 'submit';
        my $name  = $input->attr( 'name' ) || 'name' . $i++;
        my $value = $input->attr( 'value' );

        if ( $type eq 'hidden' ) { 
            $inputs{'hidden'}{$name} = $value;
        } else {
            $inputs{'visible'}{$name} = $value;
        }
    }
    return ( %inputs );
}

sub displayOptions {
    @options = sort @_;
    my $i = 1;
    map { say $i++ . ": $_" } @options;
}

sub selectOption {
    my $selection = shift;
    return $options[$selection - 1];
}

# Displays $prompt and collects user input
# Promts with /password/ will not echo user input
# No echo behaviour can also be enabled by setting $private
sub getUserInput {
    my ( %prompt_data, $private ) = @_;
    my $current_value  = $prompt_data{'value'};
    my $prompt         = $prompt_data{'prompt'} || '';
    # my $private        = shift || 0;
    $private = 0 unless defined $private;
    
    if ( $prompt =~ /password/i || $private ) { 
        ReadMode( 'noecho' ); 
    } else { 
        ReadMode( 'normal' ); 
    }
    say "Enter to accept current value: ($current_value)" if $current_value;
    print "$prompt: ";

    my $input = <STDIN>;

    ReadMode( 'normal' );
    print "\n";
    chomp $input;
    # Return existing value if enter. There are probably other
    # scenarios to cover.
    if ( !$input && $current_value ) {
        return $current_value;
    } else {
        return $input;
    }
}

# Merge hidden and visible hashes into a one-dimensional hash to send
# as POST data
sub prepareInputsForPost {
    my ( %inputs ) = @_;
    my %preparedInputs;
    foreach my $type ( keys %inputs ) {
        foreach my $input ( keys %{$inputs{$type}} ) {
            $preparedInputs{$input} = $inputs{$type}{$input};
        }
    }
    return ( %preparedInputs );
}

# Get input from user for visible inputs
sub getInputValues {
    my ( %inputs ) = @_;
    # Prompt for credentials
    foreach my $input ( keys %{$inputs{'visible'}} ) {
        $inputs{'visible'}{$input} = &getUserInput(
            ( 
              prompt => $input,
              value  => $inputs{'visible'}{$input}
            )
        );
    }
    return ( %inputs );
}

# Gets cookie required for login and submits credentials of not
# already logged in. Exits script on login failure
sub logIn {
    return if $LoggedIn;
    # Login form name
    my $loginFormName = 'a';

    say 'Getting login form…';

    # Get login page and set cookie (handled by $ua automatically)
    my $response = &doGet( $baseURL . 'index.cgi' );
    &setCurrentPage( $response->content );

    my ( %forms )  = &findForms();

    my ( %inputs ) = &findInputs( $forms{$loginFormName} );

    ( %inputs ) = getInputValues( %inputs );

    say 'Attempting to log in…';

    $response = &doPost( 
        $forms{$loginFormName}->attr('action' ), 
        &prepareInputsForPost( %inputs ) 
        );
    # Set panel as $currentPage
    &setCurrentPage( $response->content );
    # Must manually set the first cookie if the file doesn't exist
    # apparently
    $cookie_jar->extract_cookies( $response );
    $cookie_jar->save;

    # Check for login failure indicated by <div class='caution'>
    my ( @divs ) = &findElements( 'div', ( class => 'caution' ) );
    if ( @divs ) {
        print "Login failed\n";
        exit;
    }

    $LoggedIn = 1;
}

# Get list of domains, domain SIDs, commands, and command URLs from
# `fastsearch' JS file used by the search bar (easier than parsing the
# DOM)
sub loadOptionsJSON {
    my ( $fastsearch_script ) = &findElements( 'script', (src => qr/^fastsearch/ ));
    my $response = &doGet( $baseURL . $fastsearch_script->attr('src' ));
    ( my $json_data = $response->content ) =~ s/^[^\[]+//;

    # Note: @{…} dereferences the arrayref from decode()
    my @decoded_json = @{JSON::PP
        ->new
        ->allow_barekey
        ->allow_singlequote
        ->decode( $json_data )};

    my $domain;
    my $domain_number = 0;
    my $task_number   = 0;
    for ( my $i = 0, my $length = $#decoded_json; $i < $length ; $i += 1 ) {
        # Get domains and domain SIDs
        if ( $decoded_json[$i]{link} =~ /&dsid=/ ) {
            ( $domain = $decoded_json[$i]{text} ) =~ s/^.*(for|domain)\s([^ ]+$)/$2/;
            if ( not defined $domains{$domain} ) {
                ( my $domain_sid = $decoded_json[$i]{link} ) =~ s/.*&dsid=//;
                $domain_number += 1;
                $domains{$domain} = {
                    dsid          => $domain_sid,
                    domain_number => $domain_number
                };
            }
        } 
        # Extract tasks and related URLs related to user's domains
=pod Don't bother getting these commands; they are too limited
        if ( $domain 
            && $decoded_json[$i]{text} =~ /
                (manage|redirect)       # ignore synonyms add, edit, create
                .*
                (records\sfor|domain)   # ignore for-only variants
                \s
                $domain                 # match some found $domain
                $                       # end of record
                /x ) {
            ( my $command = $decoded_json[$i]{text} ) =~ s/
                (\sfor)?                # remove for
                \s                      # remove space
                $domain                 # remove found $domain
                $                       # end of record
                //x;
            # Only store unque tasks with links and a $task_number for CLI
            if ( not defined $tasks{$command} ) {
                # Strip off domain and dsid so links can be used for any domain
                ( my $link = $decoded_json[$i]{link} ) =~ s/(&(domain|dsid)=)[0-9a-z-\.]+/$1/;
                $task_number += 1;
                $tasks{$command} = {
                    link        => $link, 
                    task_number => $task_number
                };
            }
        }
=cut
    }
}

sub loadOptions {
    say 'loading options…';
    my ( @links ) = &findElements( 'a', (href => qr/\?tree=[^=&]+&$/ ));
    foreach my $link (@links) {
        # Extract category & task from link, see %task_categories comment
        ( my $href = $link->attr( 'href' ) )  =~ s/^.*tree=(.*)&/$1/g;
        ( my $category, my $sub_category ) = split /\./, $href;

        # $task_categories{$category} = '' unless $task_categories{$category};

        $task_categories{$category}{$sub_category} = $href;
    }
}

sub chooseTask {
    &displayOptions(keys %task_categories);
    my $choice = &getUserInput( ( prompt => 'Which category?', value => '' ) );
    my $category = &selectOption($choice);


    &displayOptions(keys %{$task_categories{$category}});
    $choice = &getUserInput( ( prompt => 'Which task?', value => '' ) );
    my $task = &selectOption($choice);
    # Update globals
    $currentTaskTree = $task_categories{$category}{$task};
    my $currentTaskUrl =  $baseURL . 'index.cgi?tree=' . $currentTaskTree . '&' ;
    # Fetch page and set
    say 'loading actions…';
    my $response = &doGet( $currentTaskUrl );
    &setCurrentPage( $response->content );
}

# There are some idiosyncracies in tasks and forms, so may need some
# distinct functions. For example, the _domains_ category generally
# require selection of a domain to perform the action on, which also
# means a queue could be established for bulk editing. But other
# categories, such as _billing_ or _storage_, there's no need.
sub chooseAction {
    # only work with links for now. Easier!
    # my ( %forms ) = &findForms();
    my ( @links ) = &findElements( 'a', ( href => qr/$currentTaskTree.*&next_step=/ ) );
    my %links = map { $_->content_list() => $_->attr( 'href' ) } @links;

    &displayOptions(keys %links );
    my $choice = &getUserInput( ( prompt => 'Which action?', value => '' ) );
    my $action = &selectOption($choice);

    # Set globals
    $currentActionText = $choice;
    $currentActionUrl  =  $baseURL . 'index.cgi' . $links{$action};

    # Fetch page and set
    say 'loading form…';
    my $response = &doGet( $currentActionUrl );

    &setCurrentPage( $response->content );

}

# Currently this function does more than just get a form for an
# action. It gets input and submits it as well. Should focus on
# refactoring this to deal with all basic forms.
sub getActionForm {

    my ( %forms )  = &findForms(1);
    # Most forms don't have a name or id, so `findForms()` gives it
    # the name `form`+ incrementor. Need to make sure this works for
    # all pages rather than hardcoding and hoping though
    my ( %inputs ) = &findInputs( $forms{'form1'} );

    ( %inputs ) = getInputValues( %inputs );

    say 'submitting form…';

    my $response = &doPost( 
        $baseURL . 'index.cgi' . $forms{'form1'}->attr( 'action' ), 
        &prepareInputsForPost( %inputs ) 
        );
    # Set panel as $currentPage
    &setCurrentPage( $response->content );

    my ( @divs ) = &findElements( 'div', ( class => 'successbox_body' ) );
    if (!@divs) {
        say 'Action failed!';
    } else {
        say $divs[0]->as_text();
    }

    &confirmExit();
}

# This function has largely been abandoned but has some ideas which
# may be used later
# Display tasks available for $currentPage, read
# selection, display available %domains to perform tasks on, read
# selection @todo refactor this or use CLI::Framework instead. Too
# procedural here.
sub doTask {
    # Display available tasks
    map { 
        print $tasks{$_}{task_number} . "\t" . $_ . "\n" ;
    } sort keys %tasks;

    # Get user selection
    my $response = &getUserInput( 'Which task?' );

    # Get task's url by matching user input to task_number
    my $task_url;
    foreach my $task ( keys %tasks ) {
        $task_url = $tasks{$task}{link} if $tasks{$task}{'task_number'} == $response
    }

    # Same procedure as above for %domains
    # @todo refactor this whole thing as noted in sub description
    map { 
        print $domains{$_}{domain_number} . "\t" . $_ . "\n";
    } sort keys %domains;

    $response = &getUserInput( 'Which domain?' );
    my $selected_domain;

    # @todo simplify this with a framework. This is becoming too
    # complicated
  FIND_DOMAIN: {
      foreach my $domain ( keys %domains ) {
          $selected_domain = $domain;
          last FIND_DOMAIN if $domains{$domain}{'domain_number'} == $response;
      }
    }
    # Add domain or dsid to url as appropriate Domain and DSID were
    # stripped off when finding domains in loadOptionsJSON() This
    # approach has been abandoned, but the idea is ok and will be
    # reimplimented in the `choseAction()` function when dealing with
    # the _domains_ category.
    $task_url .= $selected_domain                   if $task_url =~ /&domain=$/;
    $task_url .= $domains{$selected_domain}{'dsid'} if $task_url =~ /&dsid=$/;

    d($task_url, 0);

    # GET page for desired task and…
    $response = &doGet( $baseURL . 'index.cgi?' . $task_url );
    &setCurrentPage( $response->content );
    # …find available forms on thet page
    my ( %forms ) = &findForms();
    # @todo finish!
    # here are the forms found, doesn't seem to work for DNS-based tasks yet
    print Dumper keys %forms;
}

# A way out.
sub confirmExit{
    my $reallyExit = 0;
    my $response   = &getUserInput( ( prompt => 'Finished? (y/n)', value => 'y' ) );
    exit unless $response =~ /n/i;
    main();
}

# See if user is logged in by checking the cookie jar and, if a cookie
# is found, which is not often around me, test the validity by
# requesting a page and checking the `<title>` for _Panel_.
sub checkCookie() {
    return unless $cookie_jar->as_string;
    say 'Checking login status…';
    my $response = &doGet( $baseURL . 'index.cgi' );
    &setCurrentPage( $response->content );
    my ( @titles ) = &findElements( 'title' );

    $titles[0]->as_text() =~ /Panel/ && ($LoggedIn = 1);

}

sub main {
    &initBrowser();
    &checkCookie();
    &logIn();
    &loadOptions();
    &chooseTask();
    &chooseAction();
    &getActionForm();
    # &doTask();
    &confirmExit();
}

main();
