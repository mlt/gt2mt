#!/usr/bin/perl
# On Windows, use C:\Program Files\Git\usr\bin\perl.exe

use warnings;
use strict;
use Encode qw/encode/;

=head1 GNU gettext to message table converter

This file is meant to convert po files into Windows Message Compiler
(mc.exe) format for use with MESSAGETABLE resource and FormatMessage
instead of gettext.

=head2 How to use

  windmc --codepage_in=utf-8 -U --codepage_out=utf-8 messages.mc
  messages.o: ../../src/messages.rc
  	windres -o $@ $<

  prog_SOURCES += get_message.c
  prog_LDADD += messages_res.o
  messages_res.o: ../../src/messages.rc
  	windres -o $@ $<


=head2 Current limitations

=over

=item 1

Something is up with Tamil code page

  perl -pi -e 's/code_page\(1\)/code_page(57004)/' messages.rc

=item 2

However Visual Studio resource compiler does not like that either for
 non-UNICODE projects even with MBCS. So we have to remove it until
 the solution is found.

=back

=head2 Internals

=over

=cut

# defaults
my ($progname) = $0 =~ /([^\/\\]+)$/;
my %conf = (
    podir => 'po',
    srcdir => 'src.orig',
    destdir => 'src',
    missing => 'missing.csv',
    msgfile => 'messages.mc',
    func_name => 'GetString'
   );

foreach my $arg (@ARGV) {
    if ($arg =~ /--(podir|srcdir|destdir|missing|msgfile|func_name)=(.*)/) {
        $conf{$1} = $2;
    } else {
        if ($arg ne '--help' and $arg ne '-h') {
            print "Unknown argument $arg\n";
        }
        die <<END;
This tool converts the content of po files into Windows Message
Compiler(mc.exe) format for use with MESSAGETABLE resource and
FormatMessage instead of gettext.

Usage: perl $progname [option...]

Options:
  --help                      print this message
  --podir=<dir>               directory with PO files (default: po)
  --srcdir=<dir>              source code directory (default: src.orig)
  --destdir=<dir>             destination directory (default: src)
  --missing=<file>            a CSV file where to keep missing translations
                              (default: missing.csv)
  --msgfile=<file>            directory with PO files [default: po]
  --func_name=<name>          function identifier [default: GetString]
END
    }
}

# convenience
my $podir = $conf{'podir'};
my $srcdir = $conf{'srcdir'};
my $destdir = $conf{'destdir'};
my $missing = $conf{'missing'};
my $msgfile = $conf{'msgfile'};
my $func_name = $conf{'func_name'};

# Add more language mappings here
my %languages = (
    en => {
        lang => 'English',
        id => '409'
    },
    # en => {
    #     lang => 'Neutral',
    #     id => '0000'
    # },
    de => {
        lang => 'German',
        id => '0407'
    },
    eo => {
        lang => 'Esperanto',
        id => '1000'
    },
    fr => {
        lang => 'French',
        id => '040C'
    },
    pt_BR => {
        lang => 'Portuguese',
        id => '0416'
    },
    ro => {
        lang => 'Romanian',
        id => '0418'
    },
    ru => {
        lang => 'Russian',
        id => '0419'
    },
    sr => {
        lang => 'Serbian',
        id => '281A'
    },
    sv => {
        lang => 'Swedish',
        id => '041D'
    },
    ta => { 
        lang => 'Tamil',
        # windmc produces #pragma code_page(1)
        # but windres does not like it.
        # Should it be 57004??
        # bug?
        id => '0449'
    },
    uk => {
        lang => 'Ukraine',
        id => '0422'
    }
   );

use constant {
    STATE_LINESTART_FRESH => 0,
    STATE_MSGID_1 => 1,         # we saw "^m"
    STATE_MSGID_2 => 2,         # we saw "^ms"
    STATE_MSGID_3 => 3,         # we saw "^msg"
    STATE_MSGID_4 => 4,         # we saw "^msgi"
    STATE_MSGID_5 => 5,         # we saw "^msgid"
    STATE_STRING => 6,          # we saw "
    STATE_MSGSTR_1 => 7,        # we saw "^msgs"
    STATE_MSGSTR_2 => 8,        # we saw "^msgst"
    STATE_MSGSTR_3 => 9,        # we saw "^msgstr"
    STATE_LINESTART => 10,
    STATE_COMMENT => 11,
    STATE_SOURCE => 12,         # we saw "^#:"
    STATE_OBSOLETE => 13,       # we saw "^#~"

    STATE_UNDERSCORE => 101,    # we saw "_"
    STATE_GETTEXT => 102,       # we saw "_("

    STATE_OTHER => 999,
};


=item %messages

A hash of hashes storing content of PO files.

  msgid => {
    symbol => ...
    obsolete => ...
    seen => ...
    languages => {
      en => msgstr,
      ...
    }
}

B<TODO:> mark msgid as I<seen> if used in any c source file. Do not
dump non-seen messages (including obsolete translations) into mc file.

=cut

my %messages;                   # content of parsed po files
my %ids = ();                   # to deal with id collision

=item make_id()

Generate unique symbolic name from the message up to 3 tokens.

=cut

sub make_id($) {
    my $s = shift;
    my $id = 'MSG_';
    my $cnt = 0;
    my $last = '';

    my $enough_tokens = sub {
        if ($last eq '_') {
            $cnt++;
            return 1 if $cnt > 2;
            $id .= '_';
        }
        return 0;
    };

    open S, "<", \$s;
    while (read S, my $c, 1) {
        if ($last eq '\\') {
            if ($c ne '\\') {
                $last = $c;
            } else {            # \\
                $last = '';
            }
            next;
        }
        if ($c eq '%') {
            last if $enough_tokens->();
            $id .= 'PCT' unless $last eq 'PCT';
            $last = 'PCT';
        } elsif (ord('a') <= ord($c) and ord($c) <= ord('z')) {
            last if $enough_tokens->();
            $last = uc($c);
            $id .= $last;
        } elsif (ord('A') <= ord($c) and ord($c) <= ord('Z') or ord('0') <= ord($c) and ord($c) <= ord('9')) {
            last if $enough_tokens->();
            $id .= $last = $c;
        } elsif ($c eq '_' or $c eq '-' or $c eq ' ' or $c eq '=') {
            $last = '_' unless $last eq '';
        } elsif ($c eq '\\') {
            $last = $c;
        }
        last if $cnt > 2;
    }
    close S;

    if (exists $ids{$id}) {
        $ids{$id}++;
        $id .= $ids{$id};
    } else {
        $ids{$id} = 1;
    }

    return $id;
};


my $max_bytes = 0;
my $max_length = 0;

=item sanitize()

Replace newlines with %n, etc. Also append %0 at the end.  See Remarks
sections for
L<FormatMessage|https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-formatmessagew#remarks>.

We cannot do it as we go since we need to keep original msgid intact
to be able to locate such strings in source code but we need to add
sanitized version for English fallback.

=cut

sub sanitize ($) {
    my $msg = shift;

    my $length = length $msg;
    $max_length = $length if $length > $max_length;
    my $bytes = length(encode('UTF-8', $msg));
    $max_bytes = $bytes if $bytes > $max_bytes;

    return $msg =~ s/\\n/%n/rg . '%0';
};

opendir(DIR, $podir) or die "Can't open $podir: $!";
my @files = readdir(DIR);
closedir(DIR);
foreach my $file (@files) {
    next if $file !~ m/(.*)\.po$/;

    my $lang = $1;
#    die $languages{$lang};

    my $fsize = -s "$podir/$file";
    print "Processing $file";
    print ": 000%" if -t STDOUT;
    open(PO, "<", "$podir/$file") or die $!;
    %ids = ();
    my $lineno = 1;
    my $pos = 1;
    my $state = STATE_LINESTART_FRESH;
    my @states;
    my $escape = 0;
    my $oldstate;
    my $msgid = "";
    my $msgstr = "";
    my @sources;
    my $source = "";
    my $bytes = 0;
    while (read PO, my $c, 1) {
        # my $c = getc PO;
        # if (!defined($c)) {
        #     last;
        # }
        $bytes++;
        next if $c eq "\r";
        # if ($state != STATE_STRING) {
        #     $oldstate = $state;
        # }
        # Verbose debug of weird stuff
        # print "$lineno:$pos state:$state\n";
        if ($state == STATE_LINESTART_FRESH) {
            if ($c eq 'm') {
                @states = ();
                $state = STATE_MSGID_1;
            } elsif ($c eq "\n") {
                if (@states) {
                    @states = ();
                }
            } elsif ($c eq '"') {
                die "There should be no quote on new line\n @{[__FILE__]}:@{[__LINE__]} input:$lang $lineno:$pos states:@{[join(',', @states)]}\n";
                if (@states) {
                    $state = STATE_STRING;
                }
            } elsif ($c eq '#') {
                $state = STATE_COMMENT;
            }
        } elsif ($state ==  STATE_MSGID_1) {
            if ($c eq 's') {
                $state = STATE_MSGID_2;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGID_2) {
            if ($c eq 'g') {
                $state = STATE_MSGID_3;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGID_3) {
            if ($c eq 'i') {
                $state = STATE_MSGID_4;
            } elsif ($c eq 's') {
                $state = STATE_MSGSTR_1;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGID_4) {
            if ($c eq 'd') {
                $state = STATE_MSGID_5;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGID_5) {
            if ($c eq '"') {
                push(@states, $state);
                $state = STATE_STRING;
            } elsif ($c eq 'm') {
            	$state = STATE_MSGID_1;
            } elsif ($c eq "\n") {
                push(@states, $state);
                $state = STATE_LINESTART;
            } elsif ($c eq '#') {
                # This can only happen if going through obsolete stuff
                pop @states;
                $state = STATE_COMMENT;
            } elsif ($c ne ' ') {
                die "boo @{[__FILE__]}:@{[__LINE__]} input:$lang $lineno:$pos msgid:$msgid c:$c states:@{[join(',', @states)]}\n";
                $state = STATE_LINESTART_FRESH;
            }
        } elsif ($state == STATE_MSGSTR_1) {
            if ($c eq 't') {
                $state = STATE_MSGSTR_2;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGSTR_2) {
            if ($c eq 'r') {
                $state = STATE_MSGSTR_3;
            } elsif ($c eq '\n') {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_MSGSTR_3) {
            if ($c eq '"') {
                push(@states, $state);
                $state = STATE_STRING;
            } elsif ($c eq "\n") {
                push(@states, $state);
                $state = STATE_LINESTART;
            } elsif ($c ne ' ') {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_STRING) {
            # die "zz" if $c eq 'n' and ($lineno >= 1900);
            if ($c eq "\n") {
                # should not happen
                die "boo @{[__FILE__]}:@{[__LINE__]} input:$lang msg:$msgstr $lineno:$pos states:@{[join(',', @states)]}\n";
            } elsif ($c eq '"' and $escape != 1) {
                # $state = $oldstate;
                $state = pop(@states);
            } elsif (@states) {
                # and ($c ne "\\" or $escape)) {
                # if ($escape) {
                #     if ($c eq 'n') { # \n
                #         $c = "%n"    # newline fixup
                #     } else {
                #         $c = "\\$c";
                #     }
                # }
                my $old = $states[-1];
                # TODO form a string, assign later
                if ($old == STATE_MSGID_5) {
                    # die "boo $lineno: $#states\n" if $c eq '~';
                    $msgid .= $c;
                } elsif ($old == STATE_MSGSTR_3) {
                    $msgstr .= $c;
                } else {
                    die "boo\n";
                }
            }

            if ($c eq "\\" and $escape != 1) {
                $escape = 1;
            } else {
                $escape = 0;
            }
        } elsif ($state == STATE_LINESTART) {
            if ($c eq "\n") { # TODO: or undef from getc
                if (@states) {
                    my $old = pop @states;
                    if ($old != STATE_MSGSTR_3) {
                        print "$source\n";
                        die "boo @{[__FILE__]}:@{[__LINE__]} input:$lang $lineno:$pos states:@{[join(',', $old, @states)]}\n";
                    }
                    my $obsolete = 0;
                    if (@states) {
                        $old = pop @states;
                        if ($old != STATE_OBSOLETE) {
                            die "boo @{[__FILE__]}:@{[__LINE__]} input:$lang $lineno:$pos states:@{[join(',', $old, @states)]}\n";
                        } else {
                            $obsolete = 1;
                        }
                    }
                    $source = join(',', @sources);
                    @sources = ();

                    if ($msgid eq '' and $msgstr =~ /charset=([^\\n]+)\\n/) {
                        # print "  Changing encoding to: $1\n";
                        binmode PO, ":encoding($1)";
                    }
                    # Messages can be out of order in po files some
                    # may be missing generate SymbolicName & MessageId
                    # at the very end
                    if (not exists $messages{$msgid}) {
                        # Insert neutral locale
                        $messages{$msgid} = {
                            languages => {
                                en => sanitize($msgid)
                            }
                        };
                    }

                    $messages{$msgid}{'languages'}{$lang} = sanitize($msgstr);
                    $messages{$msgid}{'obsolete'} = $obsolete if $obsolete;
                    # print "*** [@{[make_id($msgid)]}] $msgid => $msgstr ($source)\n";
                    # Uncomment the line below for debugging
                    # print "*** [@{[scalar keys %ids]},@{[make_id($msgid)]}] $msgid => $msgstr ($source)\n";
                    $msgstr = "";
                    #               print "$msgid\n";
                    $msgid = "";
                    $source = '';
                    @states = ();
                }
                $state = STATE_LINESTART_FRESH;
            } elsif ($c eq '"') {
                $state = STATE_STRING;
            } elsif ($c eq 'm') {
                @states = ();
                $state = STATE_MSGID_1;
            } elsif ($c eq '#') {
                $state = STATE_COMMENT;
            }
        } elsif ($state == STATE_COMMENT) {
            if ($c eq ':') {
                $state = STATE_SOURCE;
            } elsif ($c eq "~") {
                $state = STATE_OBSOLETE; # should be last in file
            } elsif ($c eq "\n") {
                $state = STATE_LINESTART_FRESH;
            } else {
                $state = STATE_OTHER;
            }
        } elsif ($state == STATE_OBSOLETE) {
            if ($c eq 'm') {
                push(@states, $state);
                $state = STATE_MSGID_1;
            } elsif ($c eq '"') {
                # TODO: check stack for msgid or msgstr
                $state = STATE_STRING;
            } elsif ($c ne ' ' and $c ne "\n") {
                $state = STATE_LINESTART_FRESH;
            }
        } elsif ($state == STATE_SOURCE) {
            if ($c eq "\n") {
                if ($source ne '') {
                    push(@sources, $source);
                } else {
                    die "boo @{[__FILE__]}:@{[__LINE__]} input:$lang $lineno:$pos states:@{[join(',', @states)]}\n";
                    die "boo @{[__FILE__]}:@{[__LINE__]} input $lineno:$pos\n";
                }
                push(@states, $state);
                $state = STATE_LINESTART;
            } elsif ($c eq ' ') {
                push(@sources, $source) if ($source ne '');
                $source = '';
            } else {
                $source .= $c;
            }
        } elsif ($state == STATE_OTHER) {
            if ($c eq "\n") {
                $state = STATE_LINESTART_FRESH;
            }
        }
        if ($c eq "\n") {
            $lineno++;
            $pos = 1;
        } else {
            $pos++;
        }

        printf "\b\b\b\b%03d%%", int(100*$bytes/$fsize) if -t STDOUT; # and not $bytes % 10;
    }
    close(PO);
    if ($msgid ne '') {
        # TODO: mark obsoletes if it is or just merge using getc
        if (not exists $messages{$msgid}) {
            $messages{$msgid} = {
                languages => {
                    en => sanitize($msgid)
                }
            };
        }
        $messages{$msgid}{'languages'}{$lang} = sanitize($msgstr);
    }
    print "\n";
}

=item process_file()

Go through a source file replacing _("some text") with
$func_name(SYMBOLIC_NAME).

This should be called after SYMBOLIC_NAME is populated in
L</%messages> using L</make_id()> while producing C<messages.mc>.

B<TODO:> Alter only files that actually need modification, i.e. having
_(...).

=cut

sub process_file($) {
    my $file = shift;
    my $full = "$srcdir/$file";

    my $fsize = -s $full;
    print "Processing $full";
    print ": 000%" if -t STDOUT;
    open(MISSING, ">>$missing") or die $!;
    open(OUT, ">$destdir/$file") or die $!;
    print OUT <<END;
/* Generated source code. Do not edit! Do not commit! */
#include "messages.h"
END
    open(FILE, "<$full") or die $!;
    %ids = ();
    my $lineno = 1;
    my $pos = 1;
    my $state = STATE_LINESTART_FRESH;
    my @states;
    my $escape = 0;
    my $oldstate;
    my $msgid = "";
    my $msgstr = "";
    my @sources;
    my $source = "";
    my $bytes = 0;
    while (sysread FILE, my $c, 1) {
        $bytes++;
        next if $c eq "\r";

        if ($state == STATE_LINESTART_FRESH) {
            if ($c eq '_') {
                $state = STATE_UNDERSCORE;
            }
        } elsif ($state == STATE_UNDERSCORE) {
            if ($c eq '(') {
                $state = STATE_GETTEXT;
            } elsif ($c ne ' ' or $c ne "\n") {
                $state = STATE_LINESTART_FRESH;
                # I think we can get by without another stack
                print OUT '_';
            }
        } elsif ($state == STATE_GETTEXT) {
            if ($c eq '"') {
                push(@states, $state);
                $state = STATE_STRING;
            } elsif ($c eq ')') {
                if (exists $messages{$msgid}) {
                    my $symbol = $messages{$msgid}{'symbol'};
                    print OUT "$func_name($symbol";
                    # print "$lineno $msgid => $symbol\n";
                } else {
                    print MISSING "$file,$lineno,$pos,$msgid\n";
                    print OUT qq{_("$msgid"}; # yes, we have unbalanced parenthesis
                }
                $msgid = '';
                $state = STATE_LINESTART_FRESH;
                @states = ();
            } elsif ($c ne ' ' and $c ne "\n") { # #define _(string) gettext(string)
                print OUT '_(';
                $state = STATE_LINESTART_FRESH;
            }
        } elsif ($state == STATE_STRING) {
            if ($c eq '"' and $escape != 1) {
                $state = pop(@states);
            } elsif (@states) {
                my $old = $states[-1];
                if ($old == STATE_GETTEXT) {
                    $msgid .= $c;
                } else {
                    die "boo";
                }
            }
            if ($c eq "\\" and $escape != 1) {
                $escape = 1;
            } else {
                $escape = 0;
            }
        }

        if ($c eq "\n") {
            $lineno++;
            $pos = 1;
        } else {
            $pos++;
        }

        if ($state != STATE_UNDERSCORE and $state != STATE_GETTEXT and $state != STATE_STRING) {
            print OUT $c;
        }

        printf "\b\b\b\b%03d%%", int(100*$bytes/$fsize) if -t STDOUT; # and not $bytes % 10;
    }
    close(FILE);
    close(MISSING);
    close(OUT);
    print "\n";
#    die "done\n";
};

=item process_dir()

Recursivly traverse directories looking for c/c++ source files and
call L</process_file()> on each.

=back

=cut

sub process_dir {
    my $reldir = shift;

    my $fulldir = "$srcdir/$reldir";
    opendir(SRCDIR, $fulldir) or die "Cannot open $srcdir\n";
    my @files = readdir(SRCDIR);
    closedir(SRCDIR);
    foreach my $file (@files) {
        next if $file eq '.' or $file eq '..';
        my $full = "$reldir/$file";
        if (-d "$srcdir/$full") {
            mkdir("$destdir/$full", 0700);
            process_dir($full);
        } elsif ($file =~ /\.c(pp)?$/) {
            process_file($full);
        }
    }
};

mkdir($destdir, 0700);

# Produce message file and set up symbol

open(MSG, ">:encoding(utf-16le)", "$destdir/$msgfile") or die $!;
print MSG <<END;
;#ifndef __MESSAGES_H__
;#define __MESSAGES_H__
;
;typedef unsigned long DWORD;
;char* $func_name(DWORD msgid);

MessageIdTypedef=DWORD

LanguageNames=(
END
while (my ($lang, $v) = each %languages) {
    my %h = %$v;
    print MSG "    $h{'lang'}=0x$h{'id'}:MSG0$h{'id'}\n"
}
print MSG ")\n\n";

my $id = 1;
foreach my $msgid (keys %messages) {
    my $symbol = make_id($msgid);
    $messages{$msgid}{'symbol'} = $symbol;
    # my $symbol = $h{'symbol'};
    print MSG <<END;
MessageId=$id
SymbolicName=$symbol
END
    # while (my ($lang, $msgstr) = each %{ $message{$msgid}{languages}}) {
    my $h = $messages{$msgid}{'languages'};
    my %m = %$h;
    while (my ($lang, $msgstr) = each %m) {
        if (not exists $languages{$lang}) {
            next;
        }
        my $l = $languages{$lang}{'lang'};
        print MSG <<END;
Language=$l
$msgstr
.
END
    }
    print MSG "\n";

    $id++;
}
print MSG <<END;
;
;#endif  //__MESSAGES_H__
;
END
close(MSG);


open(MISSING, ">$missing") or die $!;
print MISSING "file,lineno,pos,msgid\n";
close(MISSING);
process_dir('.');

print "Maximum message length: $max_length letters ($max_bytes bytes)\n";
