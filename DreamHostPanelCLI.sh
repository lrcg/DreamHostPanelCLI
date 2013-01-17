#!/usr/bin/env perl 

# Purpose: An automatable CLI interface to DH's Panel

# Status: Incomplete. Can login, find domains and tasks, and forms on
# the Panel pages for those tasks.

# Copyright © 2013 Myq Larson
# http://copyfree.org/licenses/gnu_all_permissive/license.txt

use strict;
use warnings;
use v5.10;

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
my $cookies = HTTP::Cookies->new();

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

# Hash of domains known to DH panel
my %domains;

# Hash of possible tasks to perform
my %tasks;

my %task_categories;

# Hash of task links extracted from main Panel 
my %task_links;

# Hash of forms available on $currentPage for completion
my %forms;

# array of sorted options to display for user selection
my @options;

# Setup browser
# Returns nothing
sub initBrowser {
    $ua = LWP::UserAgent->new;
    $ua->agent( "DHAutomater/0.1 " );
    $ua->cookie_jar( $cookies );
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
sub findForms {
    my ( @forms ) = &findElements( 'form' );
    my %forms;
    my $form_name;

    foreach my $form ( @forms ) {
        $form_name = $form->attr( 'name' );
        if ( $form_name ) {
            $forms{$form_name} = $form;
        }
    }
    return ( %forms );
}

# Finds all inputs of a $form object from findForms(), technically a
# DOM fragment
sub findInputs {
    my ( $form ) = @_;
    my %inputs;

    my @inputs = $form->find_by_tag_name( 'input' );
    foreach my $input ( @inputs ) {
        my $name  = $input->attr( 'name' );
        my $value = $input->attr( 'value' );
        if ( defined $name ) { 
            $inputs{$name} = $value;
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
    my $prompt  = shift;
    my $private = shift || 0;
    
    if ( $prompt =~ /password/i || $private ) { 
        ReadMode( 'noecho' ); 
    } else { 
        ReadMode( 'normal' ); 
    }

    print "$prompt: ";

    my $input = <STDIN>;

    ReadMode( 'normal' );
    print "\n";
    chomp $input;
    return $input;
}

# Gets cookie required for login and submits credentials of not
# already logged in. Exits script on login failure
sub logIn {
    return if $LoggedIn;
    # Login form name
    my $loginFormName = 'a';
    &initBrowser();

    # Get login page and set cookie (handled by $ua automatically)
    my $response = &doGet( $baseURL . 'index.cgi' );
    &setCurrentPage( $response->content );

    my ( %forms )  = &findForms();

    my ( %inputs ) = &findInputs( $forms{$loginFormName} );
    # Prompt for credentials
    foreach my $input ( keys %inputs ) {
        if ( $inputs{$input} eq "" ) {
            $inputs{$input} = &getUserInput( $input );
        }
    }

    say 'Attempting to log in…';

    # Set panel as $currentPage
    $response = &doPost( $forms{$loginFormName}->attr('action' ), %inputs);
    &setCurrentPage( $response->content );

    # Check for login failure indicated by <div class='caution'>
    my ( @divs ) = &findElements( 'div', (class => 'caution' ));
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
    }
}

sub loadOptions {
    say 'loading options…';
    my ( @links ) = &findElements( 'a', (href => qr/\?tree=[^=&]+&$/ ));
    foreach my $link (@links) {
        # Extract category from link
        # ex: https://panel.dreamhost.com/index.cgi?tree=domain.ftp&
        ( my $href = $link->attr( 'href' ) )  =~ s/^.*tree=(.*)&/$1/g;
        ( my $category, my $sub_category ) = split /\./, $href;

        # $task_categories{$category} = '' unless $task_categories{$category};

        $task_categories{$category}{$sub_category} = $href;
        # d( %task_categories, 0 );
    }

    d( {%task_categories} );
    # %categories =  map { $_->attr('href') =~ //r =>  } @links;
    exit;
    # d( @links2 );

}

# Display tasks available for $currentPage, read selection, display
# available %domains to perform tasks on, read selection
# @todo refactor this or use CLI::Framework instead. Too procedural here.
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
    # stripped off when finding domains in loadOptions()
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
    my $response   = &getUserInput( 'Finished? (y/n)' );
    exit unless $response =~ /n/i;
    main();
}

sub main {
    &logIn();
    &loadOptions();
    &doTask();
    &confirmExit();
}

main();
