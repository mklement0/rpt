#!/usr/bin/env bash

unset CDPATH

kTHIS_NAME=$(basename "$BASH_SOURCE")

# Output version number and exit, if requested. Note that the `ver='...'` statement is automatically updated by `make version VER=<newVer>` - DO keep the 'v' suffix in the variable *definition*.
[[ $1 == '--version' ]] && { ver='v0.0.0'; echo "${kTHIS_NAME} ${ver#v}"$'\nFor license information and more, see https://github.com/mklement0/rpt'; exit 0; }

# Helper function for exiting with error message due to runtime error.
#   die [errMsg [exitCode]]
# Default error message states context and indicates that execution is aborted. Default exit code is 1.
# Prefix for context is always prepended.
# Note: An error message is *always* printed; if you just want to exit with a specific code silently, use `exit n` directly.
die() {
  echo "$kTHIS_NAME: ERROR: ${1:-"ABORTING due to unexpected error."}" 1>&2
  exit ${2:-1} # Note: If the argument is non-numeric, the shell prints a warning and uses exit code 255.
}

# Helper function for exiting with error message due to invalid parameters.
#   dieSyntax [errMsg]
# Default error message is provided, as is prefix and suffix; exit code is always 2.
dieSyntax() {
  echo "$kTHIS_NAME: ARGUMENT ERROR: ${1:-"Invalid argument(s) specified."} Use -h for help." 1>&2
  exit 2
}

# Recognized scale (multiplier, factor) suffixes
kSCALE_SUFFIXES=(    k     m       g             ki    mi      gi  )
kMULTIPLIERS=(       1000  1000000 1000000000    1024 1048576  1073741824 )

kUNIT_SUFFIX_MAX_CHARS='c'
kUNIT_SUFFIX_EXACT_CHARS='f'

kDEFAULT_NUMBERED_LINES_FORMAT='line %.0f'

# The pseudo-count that represents infinite ("forever") output.
kIDCHAR_ENDLESS='x'

kDICT_DEFAULT='/usr/share/dict/words'


# Command-line help.
if [[ "$1" == '--help' || "$1" == '-h' ]]; then
  cat <<EOF

SYNOPSIS
  Repeat static text:
    $kTHIS_NAME [-c] [fmtOpts] count[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS][,[perLineCount[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS]]] [text]
  Generate numbered lines:
    $kTHIS_NAME [-c] -n        lineOrByteCount[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS] [fmtText]
  Output random lines from a file:
    $kTHIS_NAME [-c] -l        lineOrByteCount[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS] file
  Generate random words:
    $kTHIS_NAME [-c] -w        count[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS][,[perLineCount[$kUNIT_SUFFIX_MAX_CHARS|$kUNIT_SUFFIX_EXACT_CHARS]]] [dictFile]
  Generate random bytes:
    $kTHIS_NAME [-c] -b        byteCount

DESCRIPTION
  Repeats static or random things a specifiable number of times or until a
  target character or byte count is reached, typically to create test data.
  Output is sent to stdout.

  The count suffixes '$kUNIT_SUFFIX_MAX_CHARS' and '$kUNIT_SUFFIX_EXACT_CHARS' specify
  that the count is to be interpreted as the *target character count*, with the
  repeat unit repeated as often as necessary to produce the desired character
  count:
  '$kUNIT_SUFFIX_MAX_CHARS' produces *at most* the specified count, without
  truncating the last repeat unit;
  '$kUNIT_SUFFIX_EXACT_CHARS' produces *exactly* as many characters as specified,
  truncating the last repeat unit as needed.

  Note that character count doesn't necessarily equal byte count, if the active
  locale uses UTF-8 character encoding, as is typical nowadays.
  If you prefix invocation with \`LC_ALL=C $kTHIS_NAME ...\`, characters will
  equal bytes, but note that you may end up splitting multi-byte characters
  apart at the end of the last repeat overall / per-line repeat unit.

  Separately, counts - except for <perLineCount> - can be scaled with a
  *scale suffix*:
      ${kSCALE_SUFFIXES[*]}
    representing the following multipliers ('i' denotes binary ones):
      ${kMULTIPLIERS[*]}
  E.g., '2k' represents 2,000, '1gi' represents 1,073,741,824 (1024^3).
  Use of a scale suffix allows you to specify the number as a float; e.g.,
  '.5k' for 500, or '1.5mib' for 1,572,864 (1.5 * 1024^2) bytes.
  Be careful with large multipliers, as the resulting data can take
  a long time to produce.

  Specify '$kIDCHAR_ENDLESS' as a count to produce endless output, except with the -n option.

  -c (all synopsis forms)
    count-only: only outputs the total count of *bytes* that *would* be 
    generated, without actually generating data, as an unscaled integer.
    This is useful to calculate effective storage size and also for measuring
    measuring the (total) byte length of <text> containing multi-byte chars.
    Caveat: with the -w and -l options, unless <count> is suffixed with '$kUNIT_SUFFIX_EXACT_CHARS',
    the resulting count may vary with each invocation, due to length variations
    in the randomly selected words / lines.

  1st synopsis form: Repeat static text:

    If <text> is not given, input is read from stdin (all at once).
  
    Appending ',' to the count, optionally followed by a per-line repeat
    count, switches to *line-based output*.

    The per-line repeat count specifies how many instances of <text> to place
    on each output line and thus controls the length of each output line.
    Note that a scale suffix is not supported; the optional unit suffixes
    work analogously to the primary-count ones:
    '$kUNIT_SUFFIX_MAX_CHARS' produces *at most* the specified count of 
    characters per line, without truncating the last repeat unit;
    '$kUNIT_SUFFIX_EXACT_CHARS' produces *exactly* as many characters as specified
    per line, truncating the last repeat unit as needed.

    By default, multiple instances of the input on a given line are directly
    concatenated to one another, without a separator or other formatting.
    <fmtOpts> allow you to modify this behavior:
        -s sep (default: none)
          The separator to place between instances.
        -d delims (default: none)
          The delimiters to put around each instance. If <delims> is a single
          char, that same char. is placed before and after the instance;
          otherwise, the first *half* of <delims> is placed before, and the
          other after the instance.
        -t terminator (default: none)
          The terminator to unconditionally place after ever instance; similar
          to a separator, except that it also placed after the *last* instance.
      These options are combined as follows:
        <delimsOpen>...<delimsClose><terminator><sep>

  2nd synopsis form: Generate numbered lines starting with 1:

    Note: This form relies on the presence of Perl.

    -n ... outputs sequentially numbered lines
      If <fmtText> is not specified, the default is '$kDEFAULT_NUMBERED_LINES_FORMAT',
      resulting in 'line 1', 'line 2', ...
      <fmtText> is a printf format string to apply to each output line; it may
      contain arbitrary text combined with exactly one format specifier for
      the line number, typically, based on \`%.0f\`, which supports the largest
      range of (effective) integers.
      You may specify a fixed field width, with either left-space padding
      (e.g., '%4.0f') or left-zero-padding (e.g., '%04.0f').

  3rd synopsis form: Output random lines from a file:

    Note: This form relies on the presence of Perl.

    <file> must be a seekable file; therefore, stdin input, process
    substitutions and FIFOs are not supported.

    Note that the output may contain duplicate lines from the input file even
    if the number of lines selected to produce the output is smaller than the
    number of lines in the input file.

  4th synopsis form: Generate random words:

    Note: This form relies on the presence of Perl.

    <dictFile> defaults to $kDICT_DEFAULT, which means that by default
    random words from the system's English dictionary are output.
    If specified, <dictFile> must be a seekable file; therefore, stdin input,
    process substitutions and FIFOs are not supported. Each word in
    <dictFile> must be on its own line.

    The count spec. follows the same rules as in the 1st synopsis form:
    single-line output by default, which can be switched to multi-line output
    by appending ',', optionally followed by the desired per-line count of
    words. Multiple words on a line are separated with a single
    space.

  5th synopsis form: Generate random bytes:

    Outputs <byteCount> random bytes, generated via /dev/urandom.
    Note that the output typically includes non-printable characters,
    including NUL.

EXAMPLES
  $kTHIS_NAME 3 .         # -> '...'
  $kTHIS_NAME 3, 'ab'     # -> $'ab\nab\nab\n'
  $kTHIS_NAME 10,80 .     # -> 10 lines with 80 '.' chars. each
  $kTHIS_NAME 1kib,80 . > out # create 1024-byte file 'out' filled 
                              # with lines of 80 '.' chars. each
  $kTHIS_NAME -b .5ki > out # create file 'out' with 512 random bytes
  $kTHIS_NAME -c 1 'Hï'     # -> 3, the number of bytes in the string (UTF8)
EOF
  exit 0
fi


# SYNOPSIS
#   repeat [-b] [-s sep] [-d delim] [-t trm] count [text...]
# DESCRIPTION
#   Repeats (replicates) string <text> <count> times. NO \n is automatically appended to the output.
#   <count> may be 'x' to specify endless output.
#   If <text> is not specified, its value is read from stdin.
#     -b
#        Makes <text> *subject to interpretation of backslash escape sequences* (e.g., '\n') - off by default.
#        Note that, by contrast, backslash escape sequences in <sep>, <delim>, and <trm> are *always* interpreted.
#     -s sep (default: empty)
#       Specifies a separator string to place *between* instances of <text>.
#     -d delimiter (default: empty)
#       Specifies a delimiter string to place *around* instances of <text>.
#       If <delimiter> is a single char., that char is used as both the opening and closing delimiter.
#       Otherwise, the first half of <delimiter> is used as the opening one, and the 2nd half as the closing one.
#     -t trm (default: empty)
#       Specifies a terminator string to place *after* every instance of <text>, including the last one.
#       If a separator is also specified, it comes after the terminator.
# IMPLEMENTATION NOTES
#   Uses perl, if available, awk otherwise.
# EXAMPLES
#      repeat 3 'c' # -> 'ccc' 
#      repeat -s @ 5 'c' # -> 'c@c@c' 
#      repeat -s ' ' 3 'a\b' - # -> 'a\b a\b \ab' 
#      repeat -b 3 'line\n' - # -> $'line\nline\nline\n' (3 lines)
#      repeat -s ' ' -d '[]' 3 'a' - # -> '[a] [a] [a]' 
repeat() {
  local OPTARG= OPTIND=1 opt interpret sep delimInterpreted delimOpen delimClose trm count fmt txtRaw txt txtUnit endless
  interpret=0 sep= delimOpen= delimClose= trm= endless=0 # defaults
  while getopts ':bs:t:d:' opt; do
    [[ $opt == '?' ]] && { echo "ARGUMENT ERROR: Unknown option: -$OPTARG" >&2; return 2; }
    [[ $opt == ':' ]] && { echo "ARGUMENT ERROR: Option -$OPTARG is missing its argument." >&2; return 2; }
    case "$opt" in
      b)
        interpret=1
        ;;
      s)
        printf -v sep %b "$OPTARG" # always interpret escape sequences
        ;;
      d)
        printf -v delimInterpreted %b "$OPTARG" # always interpret escape sequences
        if (( ${#delimInterpreted} == 1 )); then
          delimOpen=$delimInterpreted
          delimClose=$delimOpen
        else
          delimOpen=${delimInterpreted: 0: ${#delimInterpreted} / 2}
          delimClose=${delimInterpreted: ${#delimOpen}}
        fi
        ;;
      t)
        printf -v trm %b "$OPTARG" # always interpret escape sequences
        ;;
      *)
        { echo "DESIGN ERROR: option -$opt not handled." >&2; return 3; }
        ;;
    esac
  done
  shift $((OPTIND - 1)) # Skip the already-processed arguments (options).

  # Validate the count and convert it to a decimal.
  if [[ $1 == 'x' ]]; then
    endless=1
  else
    count=$(set -u; echo $(( $1 ))) >/dev/null # Sadly, Bash's error message in the event that the input is not a number cannot be suppressed.
    [[ -n $count ]] && (( count >= 0 )) || { echo "ARGUMENT ERROR: '$1' is not a valid repeat count. Please specify an integer >= 0 in either decimal, hex, or octal form." >&2; return 2; }
  fi
  shift

  if (( $# == 0 )); then # read from stdin - all input at once.
    IFS= read -d $'\x4' -r txtRaw # !! $'\x4' is required to support interactive (all-lines-at-once) input that can be terminated with ^D.
  else # all remaining operands (though typically only 1)
    txtRaw=$*
  fi

  # Determine the printf format to apply, depending on whether backslash escape sequences in the input should be interpreted or not.
  (( interpret )) && fmt='%b' || fmt='%s'

  # Determine the dressed-up unit of text to replicate.
  txtUnit="${delimOpen}${txtRaw}${delimClose}${trm}" # delimiters and terminator applied - but NOT the separator
  # With a separator specified, we append it to the unit, but only print count *minus 1* instances,
  # so that we can print the final instance without separator afterward.
  # !! We need an explicit 'if' statement to guard the (( --count )) command - otherwise, with a non-numeric $count, the entire command grouping is silently aborted.
  [[ -n $sep ]] && { txt="${txtUnit}${sep}"; if (( ! endless )); then (( --count )); fi } || txt=$txtUnit

  if (( endless )); then
    # Note: execution effectively ends here: this endless loop only ends when the script is externally terminated.
    while :; do printf "$fmt" "$txt"; done
  elif (( count )); then
    if [[ -n $(command -v perl) ]]; then # use Perl, if available: it's much faster with high repeat counts.
      # echo "[??perl]"
      # Note that we must pass the count as an ad-hoc *environment* variable, since we're using -n
      # to pass the (interpreted) text as a file (we pass the text via stdin, because using
      # a variable that captures the output from printf using a command substitition would eat trailing newlines).
      # !! For FreeBSD compatibility we avoid process substitution.
      printf "$fmt" "$txt" | count=$count perl -0777 -C -ne 'print $_ x $ENV{count};'
    else # otherwise: use awk: still reasonably fast, but perl is much faster esp. with high repeat counts.
      # echo "[??awk]"
      # Note that we pass the text as a *file* rather than with `-v var=value`, because that
      # way we can pass multi-line strings and control if and when backslash interpretation occurs.
      # (Such interpretation is *invariably* applied to `-v var=...` values.)
      # !! For FreeBSD compatibility we avoid process substitution.
      # !! Do NOT use `NF=101`, because it crashes BSD awk.
      printf "$fmt" "$txt" | awk -v count=$(( count + 1 )) -v RS=$'\3' -v ORS= 'BEGIN { getline OFS; $count=""; print }'
    fi
  fi

  [[ -n $sep ]] && (( count >= 0 )) && printf "$fmt" "$txtUnit" # print last instance without trailing separator

  return 0
}


# SYNOPSIS
#   repeat_singleByte count single-byte-char
# DESCRIPTION
#   If <count> is 'x', endless output is produced.
#   If Perl is not available, this is a more efficient alternative to repeat() for a given single byte.
# IMPLEMENTATION NOTES
#   Uses Perl, if available, head -c otherwise. Perl is much faster.
#   E.g.: Creating 10^9 bytes (1 metric GB) on a 3.2 Ghz machine takes about 3.5 secs with perl, almost 2 minutes(!) with head -c + tr (and around 6 minutes with awk).
repeat_singleByte() {
  if [[ $1 == 'x' ]]; then # endless output
    tr '\0' "$2" < /dev/zero  # Note: We don't bother with trying to create a potentially faster Perl solution in this case.
  else
    if [[ -f $(command -v perl) ]]; then # use Perl, if available: it's much faster with high repeat counts.
        perl -e 'print $ARGV[1] x $ARGV[0];' "$1" "$2"
    else # otherwise, use head -c + tr, which is (a) much slower, and (b), not POSIX-compliant (while POSIX tail has a -c option for bytes, head does not).
      ## use dd (as POSIX utility), which is much slower, however.
      # # !! `dd` accepts a maximum of 2147483647 as the block size, so we need to *chunk* the output accordingly.
      # local passes=$(( $1 / 2147483647 )) rest=$(( $1 % 2147483647 )) thisPassByteCount i
      # for (( i = 0; i <= $passes; i++ )); do
      #   (( i == passes )) && thisPassByteCount=$rest || thisPassByteCount=2147483647
      #   dd if=/dev/zero bs=$thisPassByteCount count=1 2>/dev/null | tr '\0' "$2" || return
      # done
      head -c "$1" /dev/zero | tr '\0' "$2"
    fi
  fi
}

# Outputs the specified number of random bytes.
repeatRandomBytes() {
  local count=$1 srcFile='/dev/urandom'
  if [[ $count == "$kIDCHAR_ENDLESS" ]]; then
    cat "$srcFile"
  else
    head -c "$count" "$srcFile"
  fi
}

# SYNOPSIS
#     getRandomLines [-s sep] lineCount[,inputLinesOrCharCountPerOutLine[c|f]] [file]
# DESCRIPTION
#   Gets random lines (duplicates possible) from <file> and outputs them on a specifiable number 
#   of lines, on each of which one (by default) or multiple input lines may be placed, separated by <sep>.
#
#   -s sep   (default: space) specifies the string to use to separate multiple input lines placed on a single output line.
#
#   <file> defaults to /usr/share/dict/words, the standard English dictionary, and must be an actual, seekable
#   file - FIFOs and process substitutions won't work.
#
#   lineCount ... the number of output lines to produce:
#       'x' keeps producing output lines indefinitely.
#       1 creates a single output line without trailing '\n'.
#     inputLinesOrCharCountPerOutLine[cC] ... the number of input lines to place on each output, or, with a suffix, the
#       exact (f) or max. (c) line length to produce with repeated input lines; in either case, input lines are separated with <sep>.
#       'x' keeps putting input lines on a single output line indefinitely, until terminated.
#       Suffixes:
#         (none) ... treat the count as the number of input lines to place on each output line; output lines may therefore vary in length.
#         c ... treat the char. count as a *maximum* and put only as many input lines on the ouptut line as will fit in full without exceeding the max. count.
#             Output lines may therefore vary in length and may even be empty.
#         f ... enforce the *exact char. count* and cut off the last input line placed on an output line as needed - all output lines will have the same length.
# PREREQUISITES
#   Perl 5.10
# NOTES
#   Gratefully adapted from http://stackoverflow.com/a/29119495/45375
# EXAMPLES
#   getRandomLines 10  # get 10 random words from /usr/share/dict/words, one per line.
#   getRandomLines 1,3  # get 3 random words from /usr/share/dict/words, separated with a space each, on a single line
#   getRandomLines 2,78c  # output 2 lines filled with random, full words up to a max. of 78 chars.
#   getRandomLines 2,78f  # output 2 lines, each exactly 78 chars. long, filled with random, words, with the last one possibly cut off
#   getRandomLines 3 ~/.bashrc # get 3 random lines from ~/.bashrc
#   getRandomLines -s "@" 10,3 file #  output 2 lines, each filled with 3 "@"-separated random lines from file 'file'.
getRandomLines() {
  local OPTARG= OPTIND=1 opt sep=
  while getopts ':s:' opt; do
    [[ $opt == '?' ]] && { echo "ARGUMENT ERROR: Unknown option: -$OPTARG" >&2; return 2; }
    [[ $opt == ':' ]] && { echo "ARGUMENT ERROR: Option -$OPTARG is missing its argument." >&2; return 2; }
    case "$opt" in
      s)
         printf -v sep '%b' "$OPTARG" # interpret escape sequences in the separator
         ;;
      *)
        { echo "DESIGN ERROR: option -$opt not handled." >&2; return 3; }
        ;;
    esac
  done
  [[ -n $sep ]] || sep=' ' # default to single space
  shift $((OPTIND - 1)) # Skip the already-processed arguments (options).
  # !! We do NOT use -C (or "use open ':locale'") here, because the Perl script uses low-level I/O that
  # !! requires reading the file in binary mode, and it simply returns the bytes comprising a line 'as is'.
  perl -- - "$1" "${2:-/usr/share/dict/words}" "$sep" <<'EOF'
use strict;
use warnings;
use Symbol;
use Fcntl qw( :seek O_RDONLY ) ;
my $seekdiff = 512; # max. line length in bytes
# Note that even though the buffer extracted below is 2 * $seekdiff bytes long, we don't know where that falls relative to the beginning of a line.
# So, in the worst-case scenario, the 1st (and possibly only) `\n` in the buffer is
# at byte position $seekdiff, which means that the longest line you can fully return is $seekdiff bytes long.

my($countSpec, $file, $sep) = @ARGV;
$countSpec =~ /^(\d+|x)(,((\d+|x)([cf])?)?)?$/ || die "Unrecognized count specification: " . $countSpec;
my $lineCount=$1;
my $perLineCount = 1;
my $perLineCountIsChars = 0;
my $enforceCharCount = 0;
if ($2) {
  $perLineCount = $4 || 1;
  if ($5) {
    $perLineCountIsChars = 1;
    $enforceCharCount = $5 eq 'f';
  }
}
my $endlessLines = $lineCount eq 'x';
my $endlessCols = $perLineCount eq 'x';


my $fd = gensym; # create a symbolic name to use as the file descriptor
sysopen($fd, $file, O_RDONLY ) || die "Cannot open $file: $!";
binmode $fd; # !! important for low-level I/O to work as expected.
my $endpos = sysseek( $fd, 0, SEEK_END ) || die "Cannot seek: $!";

my $buffer;
my $lineCountSoFar;
while ($endlessLines || $lineCount > $lineCountSoFar++) { # line loop

  # Edge case: if the per-line count is 0, all we do is print a newline.
  do { print "\n"; next; } if ! $endlessCols && $perLineCount == 0;

  my $perLineCountSoFar = 0;
  my $thisSep = "";
  my $outLine = "";
  while (1) { # line-internal loop

    # Get a random input line.
    my $randpos = int(rand($endpos)); # random file position
    my $seekpos = $randpos - $seekdiff; # start read here ($seekdiff chars before)
    $seekpos = 0 if( $seekpos < 0 );

    sysseek($fd, $seekpos, SEEK_SET); # seek to position
    my $in_count = sysread($fd, $buffer, $seekdiff<<1); # read 2*seekdiff characters - see explanation for max. line length above

    my $rand_in_buff = ($randpos - $seekpos)-1;

    my $linestart = rindex($buffer, "\n", $rand_in_buff) + 1; # find the begining of the line in the buffer
    my $lineend = index $buffer, "\n", $linestart; # find the end of line in the buffer
    my $the_line = substr $buffer, $linestart, $lineend < 0 ? 0 : $lineend - $linestart;

    if ($endlessCols) {
      print "$thisSep$the_line";
    } elsif ($perLineCountIsChars) { # fixed or max. number of chars. on line
      # Keep building the line as long as it's shorter than the target length.
      my $nextLength = length($outLine) + length($thisSep) + length($the_line);
      if ($enforceCharCount || $nextLength <= $perLineCount) {
        $outLine .= "$thisSep$the_line"
      }
      if ($nextLength >= $perLineCount) {
        print substr $outLine, 0, $perLineCount;
        last;        
      }
    } else {  # fixed number of words
      print "$thisSep$the_line";
      last if ++$perLineCountSoFar == $perLineCount;
    } 
    $thisSep = $sep if length($thisSep) == 0;

  } # line-internal loop

  print "\n" if $endlessLines || $lineCount > 1;

} # end of Perl code
EOF
}

# SYNOPSIS
#   headChars <charCount>
# DESCRIPTION
#   Extracts the first <charCount> characters from text provided via stdin.
#   Similar to `head -c`, except that *characters* rather than bytes are
#   counted, in a locale-aware fashion.
# PREREQUISITES
#   Requires Perl.
# EXAMPLE
#   headChars 2 <<<Hübl # -> 'Hü'
headChars() {
  local count=$1
  count=$count perl -C -pe '
    BEGIN { $count = $ENV{count}; $countSoFar = 0; }
    $len = length($_);
    if ($countSoFar + $len > $count) {
      print substr($_, 0, $count - $countSoFar);
      exit
    }
    $countSoFar += $len;
  '
}

# SYNOPSIS
#   generateNumberedLines count[c|f] [fmt]
# DESCRIPTION
#   Generates <count> numbered lines or, if <count> is suffixed with 'c' or 'f',
#   as many numbered lines as needed until the desired character count is
#   reached:
#   'c' produces *at most* <count> characters, without truncating the last
#   output line.
#   'f' produces *exactly* <count> characters (fixed count, truncating the
#   last output line as needed.
#
#   Note that a character count doesn't necessarily equal the same byte count,
#   if the active locale uses UTF-8 character encoding, as is typical nowadays.
# 
#   <fmt> is a printf format string that defaults to 'line %.0f'.
#   
# PREREQUISITES
#   Requires Perl.
# EXAMPLE
#   generateNumberedLines 10  # -> $'line 1\nline 2\n...'
#   generateNumberedLines 1000c 'line %03d' # -> $'line 001\n...' up to a *max.* of 1000 chars.
#   generateNumberedLines 1000f # -> $'line 1\nline 2\n...' with *exactly* 1000 chars.
generateNumberedLines() {

  local count=$1 fmt=${2:-'line %.0f'}

  perl -C -we '
    BEGIN { 
      ($count, $fmt) = @ARGV;
      $fmt .= "\n";
      $exact = 0; $maxChars = 0; $charsSoFar = 0;
      if ($count =~ /^(\d+)([cf])$/i) {
        $count = $maxChars = $1;
        $exact = $2 eq "f";
      }
    }
    for ($i=1; $i <= $count; ++$i) {
      $line = sprintf $fmt, $i; $chars=length($line);
      if ($maxChars && $charsSoFar + $chars >= $maxChars) {
        if ($exact) {
          $line = substr $line, 0, $maxChars - $charsSoFar;
          $i = $count; # exit after this iteration
        } else {
          last;
        }
      }
      print $line;
      $charsSoFar += $chars;
    }
  ' "$count" "$fmt"
}


# Converts all arguments to *decimal integers* (i.e.: strings representing the input number with base 10), if possible, and outputs one number per line.
# By default, positive and negative integers are accepted, but when invoked by a function named 'toPosInt', only positive (>= 0) integers are accepted.
# Acceptable number formats are: DECIMAL, HEX (PREFIX '0x' OR '0X'), OCTAL (PREFIX '0') - LEADING AND TRAILING WHITESPACE IS IGNORED.
# Exit code is 0 if ALL arguments were recognized as numbers of the expected type, 1 otherwise - processing stops with the first argument that's not a number.
# Examples:
#   n=$(toInt $1) || echo "$1 is not an integer."
#   toInt 0x10 010 -77 # -> $'16\n8\n-77'
# See also: isInt()
toInt() {
  local nRaw n positiveOrZeroOnly=0 basePrefix digits
  [[ ${FUNCNAME[1]} == 'toPosInt' ]] && positiveOrZeroOnly=1
  (( $# )) || return 1  # no input -> not an integer
  for nRaw in "$@"; do
    # !! Sadly, blindly trying to convert with $(( ... )) results in *instant return with error code 1 and an error message that cannot be suppressed* for numbers with invalid bases such as '08'.
    # !! Conversely, a non-number - such as whitespace or text that could be a variable name - silently results in output '0'.
    # !! (We could use `set -u` in a subshell to trigger errors in case of undefined variables, but there could still be accidental matches with currently defined shell variables.)
    # !! Thus, we try to weed out non-numbers or invalid numbers with a regex first, but limit ourselves to the most frequently used number bases: decimal, octal, hex.
    # We accept, in order:
    #   optional: leading whitespace
    #   optional: either + or - sign
    #   optional: base prefix:
    #      0 ... octal
    #      0x or 0X .. hex
    #   mandatory: at least 1 digit
    #   optional: trailing whitespace
    [[ $nRaw  =~ ^[[:space:]]*[-+]?(0[xX]?)?([0-9A-Fa-f]+)[[:space:]]*$ ]] || return 1
    basePrefix=${BASH_REMATCH[1]} digits=${BASH_REMATCH[2]}
    case "$basePrefix" in
      0x|0X) # hex
        : # already validated by the regex above
        ;;
      0) # octal
        [[ $digits =~ ^[0-7]+$ ]] || return 1
        ;;
      *) # decimal
        [[ $digits =~ ^[0-9]+$ ]] || return 1
        ;;  
    esac
    # At this point we can confidently convert to a decimal using $(( ... )).
    n=$(( nRaw )) || return 1
    # If requested, ensure that the number is >= 0.
    (( positiveOrZeroOnly && n < 0 )) && return 1
    echo "$n"
  done
  return 0
}


# Converts all arguments to *positive (>=0) decimal integers* (i.e.: strings representing the input number with base 10), if possible, and outputs one number per line.
# See toInt() for details.
# Example:
#   n=$(toPosInt $1) || echo "$1 is not a positive integer."
toPosInt() { toInt "$@"; } # !! NO extra arg needed; toInt() modifies its behavior based on the name of the invoking function.

# SYNOPSIS
#     indexOf needle "${haystack[@]}"
# *Via stdout*, returns the zero-based index of a string element in an array of strings or -1, if not found.
# The *return code* indicates if the element was found or not.
# EXAMPLE
#   a=('one' 'two' 'three')
#   ndx=$(indexOf 'two' "${a[@]}") # -> $ndx is now 1
indexOf() {
  local e ndx=-1
  for e in "${@:2}"; do (( ++ndx )); [[ "$e" == "$1" ]] && echo $ndx && return 0; done
  echo '-1'; return 1
}

# -------------------------


randomBytes=0
countBytesOnly=0
numberedLines=0
randomWords=0
randomLines=0
repeatFmtOpts=()
sep=
# ----- BEGIN: OPTIONS PARSING: This is MOSTLY generic code, but:
#  - SET allowOptsAfterOperands AFTER THIS COMMENT TO 1 to ALLOW OPTIONS TO BE MIXED WITH OPERANDS rather than requiring all options to come before the 1st operand, as POSIX mandates.
#  - The SPECIFIC OPTIONS MUST BE HANDLED IN A CASE ... ESAC STATEMENT BELOW; look for "BEGIN: CUSTOMIZE HERE ... END: CUSTOMIZE HERE"
#  - Assumes presence of function dieSyntax(); if not present, define as: dieSyntax() { echo "$(basename -- "$BASH_SOURCE"): ARGUMENT ERROR: ${1:-"Invalid argument(s) specified."} Use -h for help." >&2; exit 2; }
#  - After the end of options parsing, $@ only contains the operands (non-option arguments), if any.
allowOptsAfterOperands=1 operands=() i=0 optName= isLong=0 prefix= optArg= haveOptArgAttached=0 haveOptArgAsNextArg=0 acceptOptArg=0 needOptArg=0
while (( $# )); do
  if [[ $1 =~ ^(-)[a-zA-Z0-9]+.*$ || $1 =~ ^(--)[a-zA-Z0-9]+.*$ ]]; then # an option: either a short option / multiple short options in compressed form or a long option
    prefix=${BASH_REMATCH[1]}; [[ $prefix == '--' ]] && isLong=1 || isLong=0
    for (( i = 1; i < (isLong ? 2 : ${#1}); i++ )); do
        acceptOptArg=0 needOptArg=0 haveOptArgAttached=0 haveOptArgAsNextArg=0 optArgAttached= optArgOpt= optArgReq=
        if (( isLong )); then # long option: parse into name and, if present, argument
          optName=${1:2}
          [[ $optName =~ ^([^=]+)=(.*)$ ]] && { optName=${BASH_REMATCH[1]}; optArgAttached=${BASH_REMATCH[2]}; haveOptArgAttached=1; }
        else # short option: *if* it takes an argument, the rest of the string, if any, is by definition the argument.
          optName=${1:i:1}; optArgAttached=${1:i+1}; (( ${#optArgAttached} >= 1 )) && haveOptArgAttached=1
        fi
        (( haveOptArgAttached )) && optArgOpt=$optArgAttached optArgReq=$optArgAttached || { (( $# > 1 )) && { optArgReq=$2; haveOptArgAsNextArg=1; }; }
        # ---- BEGIN: CUSTOMIZE HERE
        case $optName in
          c|count-only)
            countBytesOnly=1
            ;;
          n|numbered-lines)
            numberedLines=1
            ;;
          b|random-bytes)
            randomBytes=1
            ;;
          w|random-words)
            randomWords=1
            ;;
          l|random-lines)
            randomLines=1
            ;;
          s|separator)
            needOptArg=1
            repeatFmtOpts+=( -s "$optArgReq" )
            sep=$optArgReq
            ;;
          t|terminator)
            needOptArg=1
            repeatFmtOpts+=( -t "$optArgReq" )
            ;;
          d|delimiters)
            needOptArg=1
            repeatFmtOpts+=( -d "$optArgReq" )
            ;;
          *)
            dieSyntax "Unknown option: ${prefix}${optName}."
            ;;
        esac
        # ---- END: CUSTOMIZE HERE
        (( needOptArg )) && { (( ! haveOptArgAttached && ! haveOptArgAsNextArg )) && dieSyntax "Option ${prefix}${optName} is missing its argument." || (( haveOptArgAsNextArg )) && shift; }
        (( acceptOptArg || needOptArg )) && break
    done
  else # an operand
    if [[ $1 == '--' ]]; then
      shift; operands+=( "$@" ); break
    elif (( allowOptsAfterOperands )); then
      operands+=( "$1" ) # continue 
    else
      operands=( "$@" )
      break
    fi
  fi
  shift
done
(( "${#operands[@]}" > 0 )) && set -- "${operands[@]}"; unset allowOptsAfterOperands operands i optName isLong prefix optArgAttached haveOptArgAttached haveOptArgAsNextArg acceptOptArg needOptArg
# ----- END: OPTIONS PARSING: "$@" now contains all operands (non-option arguments).

countSpec=$1; shift # Note: the count is validated below.
# Make sure that at least a count was specified.
[[ -n $countSpec ]] || dieSyntax "Too few arguments specified."

# Check for incompatible arguments - more checks below.
(( randomBytes && $# > 0 )) && dieSyntax
(( (numberedLines || randomBytes || randomLines || randomWords) && ${#repeatFmtOpts[@]} > 0 )) && dieSyntax "Incompatible arguments specified."
(( (numberedLines || randomLines || randomWords) && $# > 1 )) && dieSyntax

# ===== Perform the following case-INsensitively.
primaryCount= primaryUnit= primaryCountIsChars=0 lineBasedOutput=0 perLineCount=1 perLineUnit= perLineCountIsChars=0 perLineCharCountIsFixed=0 endless=0 endlessSingleLine=0 endlessLines=0
mustReset=$(shopt -q nocasematch; echo $?); shopt -s nocasematch

  # Split into sole/line/byte count and optional per-line count.
  [[ $countSpec =~ ^([^,]+)?(,(.*))?$ ]] || dieSyntax "'$countSpec' is not a valid count specification."

  soleOrLineOrCharCountSpec=${BASH_REMATCH[1]};
  [[ -n ${BASH_REMATCH[2]} ]] && lineBasedOutput=1  # A comma following the sole/line/byte count implies line-based output.
  perLineCountSpec=${BASH_REMATCH[3]}

  # Validate and parse the PER-LINE count spec, if specified.
  if [[ -n $perLineCountSpec ]]; then
      (( numberedLines || randomBytes || randomLines )) && dieSyntax "A per-line count is not suported with this option."
      # Parse optional per-line count.
      if [[ $perLineCountSpec =~ ^(.+)([${kUNIT_SUFFIX_MAX_CHARS}${kUNIT_SUFFIX_EXACT_CHARS}])$ ]]; then
         perLineCountIsChars=1
         perLineCount=${BASH_REMATCH[1]}
         perLineUnit=${BASH_REMATCH[2]}
         [[ $perLineUnit == "$kUNIT_SUFFIX_EXACT_CHARS" ]] && perLineCharCountIsFixed=1 || perLineCharCountIsFixed=0
      else
         perLineCount=${perLineCountSpec}
      fi
      if [[ $perLineCount == "$kIDCHAR_ENDLESS" ]]; then
        endless=1 endlessSingleLine=1
        perLineCountIsChars=0 # Note: We tolerate a unit suffix appended to $kIDCHAR_ENDLESS, even though there's no good reason to specify one.
      else
        errMsg="'${perLineCount}' is not a positive integer or has unknown suffix."
        perLineCount=$(toPosInt "${perLineCount}") || dieSyntax "$errMsg"
        errMsg=
      fi
  fi

  # Validate and parse the OVERALL sole/line/byte-count spec.
  if [[ -z $soleOrLineOrCharCountSpec ]]; then # no line/byte-count specified (which implies that the spec. started with ',': a single output line is implied

    primaryCount=1

  else

    # Split count into number and suffixes, if any (scale, unit, per-line repeat count).
    suffix=
    scaleSuffixChars=$(IFS=''; echo "${kSCALE_SUFFIXES[*]}")
    reSuffixes=$(IFS='|'; echo "${kSCALE_SUFFIXES[*]}") # since scale suffixes may be multi-char., we must construct an alternation (|) regex

    [[ $soleOrLineOrCharCountSpec =~ ^([^,${scaleSuffixChars}${kUNIT_SUFFIX_MAX_CHARS}${kUNIT_SUFFIX_EXACT_CHARS}]+)(${reSuffixes})?([${kUNIT_SUFFIX_MAX_CHARS}${kUNIT_SUFFIX_EXACT_CHARS}])?$ ]] || dieSyntax "'$soleOrLineOrCharCountSpec' is not a valid line/char-count specification."
  
    countRaw=${BASH_REMATCH[1]}; scale=${BASH_REMATCH[2]}; primaryUnit=${BASH_REMATCH[3]}

    [[ -n $primaryUnit ]] && primaryCountIsChars=1

    # Look up multiplier by scale, if specified
    multiplier=1
    if [[ -n $scale ]]; then
      multiplierNdx=$(indexOf "$scale" "${kSCALE_SUFFIXES[@]}")
      multiplier=${kMULTIPLIERS[multiplierNdx]}
    fi

    # Validate the number part:
    if [[ $countRaw == "$kIDCHAR_ENDLESS" ]]; then
      endless=1
      (( lineBasedOutput )) && endlessLines=1 || endlessSingleLine=1
      primaryCount=$kIDCHAR_ENDLESS
      primaryCountIsChars=0 # Note: We tolerate a unit suffix appended to $kIDCHAR_ENDLESS, even though there's no good reason to specify one.
    else
      # First, see if it's an integer (and convert to decimal format):
      haveInt=0
      primaryCount=$(toPosInt "$countRaw") && haveInt=1
      if (( haveInt )); then # an integer
        # Apply the multiplier.
        (( primaryCount *= multiplier ))
      else # either a float or an invalid number

        # We only accept floats with multipliers (> 1).
        (( multiplier > 1 )) || dieSyntax "'$countRaw' is not a positive integer or has unknown suffix."

        errMsg="'$countRaw' is not a positive integer or decimal fraction or has unknown suffix."

        # Validat the fload and convert it to an integer:

        # Crude test: float must start with digit or '.'
        [[ $countRaw =~ ^[0-9.] ]] || dieSyntax "$errMsg"

        # Apply the multiplier, implicitly validating the number as a float.
        # !! Sadly, bc never sets a nonzero exit code, ignores all-letter tokens silently, but at least outputs '[...] parse error' to stderr for mixed digit-letter tokens such as '1a'.
        primaryCount=$(bc <<<"$countRaw * $multiplier" 2>&1)
        [[  $primaryCount =~ 'error' ]] && dieSyntax "$errMsg"
        
        # Simply round down to nearest integer (lop off everything starting with the decimal point).
        primaryCount=${primaryCount%.*}

      fi          
    fi

  fi

  # Validate endless specs.
  (( endlessLines && endlessSingleLine )) && dieSyntax "Please use only *one* endless-output placeholder."
  (( lineBasedOutput && endlessSingleLine && primaryCount != 1 )) && dieSyntax "With endless columns, a line count other than 1 makes no sense."
  (( endlessLines && perLineCount == 0 )) && dieSyntax "With endless lines, a per-line count of 0 makes no sense."

(( mustReset )) && shopt -u nocasematch
# ======

# Produce the requested data.
# PERFORMANCE NOTES:
#  Due to our implementation, the fastest way to produce large files, in descending order:
#   * Perl with fixed string, whether single- or multi-byte
#   * random bytes (dev/urandom)
#   * No Perl: single-byte (/dev/zero + tr)
#   * No Perl: multi-char/-byte string (awk): much, much slower with high repeat counts - available RAM is an issue.
#  Example timings from a late 2012 iMac:
# $ time rpt 1.5gi x >out2  # SINGLE-BYTE or MULTI-CHAR/BYTE STRING STRING, Perl
#    ~ ca. 3 secs.(!)
# $ time rpt -r 1.5gi >out1  # RANDOM, /dev/urandom
#   real  1m53.387s
#   user  0m0.008s
#   sys 1m45.002s
# $ time rpt 1.5gi x >out2  # SINGLE-BYTE, /dev/zero + tr
#   real  3m1.468s
#   user  2m57.457s
#   sys 0m4.273s
# $ time rpt 1.5gib,79 'abc ' >out3  # MULTI-CHAR/BYTE STRING
#   real  3m22.747s
#   user  2m48.765s
#   sys 0m34.479s

# Edge cases: 
if (( countBytesOnly && endless )); then # with endless output, measuring the output size makes no sense.
  dieSyntax "Cannot count bytes in endless output."
elif (( ! endless && primaryCount == 0 )); then # Exit, if count is 0, possibly preceded by printing "0", if -c was specified.
  (( countBytesOnly )) && echo "$primaryCount"
  exit 0  # Nothing to do.
fi

if (( randomBytes )); then  # RANDOM BYTES

  # DRY RUN: only print the total count of bytes that *would* be generated and exit.
  if (( countBytesOnly )); then
    # Note: Given that the count specified is invariably interpreted as a byte count in this case,
    #       the only reason to use -c is to see what a *scaled* count amounts to in unscaled form.
    echo "$primaryCount" 
    exit 0
  fi

  # Output as many random bytes as requested or produce endless output.
  repeatRandomBytes $primaryCount || die

elif (( numberedLines )); then # NUMBERED LINES, via seq

  (( endless )) && dieSyntax "Endless output is not supported with the -n option."

  [[ -n $(command -v perl) ]] || die "This feature requires Perl, but the \`perl\` binary cannot be found."

  # Determine the format string.
  txt=${1:-$kDEFAULT_NUMBERED_LINES_FORMAT}

  cmdArgs=( generateNumberedLines "${primaryCount}${primaryUnit}" "$txt" )

  if (( countBytesOnly )); then
    # Note that due to varying line lengths we must actually run the command to measure byte size.
    # If primaryCountIsChars is true, we could in theory take a shortcut and test if the $txt contains multi-byte 
    # characters, and, if not, simply output $primaryCount (given that we only pass a number to the format string, no multi-byte
    # chars. should appear when the string is applied, right?), but for simplicity we don't - revisit, if performance is a concern.
    byteCount=$(( $("${cmdArgs[@]}" | wc -c) )) # the extra $(( ... )) is to trim the leading whitespace that BSD wc outputs.
    (( ${PIPESTATUS[0]} == 0 )) || die
    echo "$byteCount"
    exit 0
  fi

  "${cmdArgs[@]}" || die

elif (( randomLines || randomWords )); then # RANDOM LINES from a file / WORDS from the standard dictionary.

  [[ -n $(command -v perl) ]] || die "This feature requires Perl, but the \`perl\` binary cannot be found."

  if (( randomWords )); then
    file=${1:-$kDICT_DEFAULT}  # default to the system's default dictionary
  else # randomLines
    (( $# == 1 )) || dieSyntax
    file=$1
  fi

  # Make sure the file is a regular - and thus seekable - file.
  # (Fortunately, Bash reports symlinks to regular files as regular files.)
  [[ -f $file ]] || die "Cannot locate input file or it is not a regular file: '$file'."

  # Synthesize the count spec. to pass to getRandomLines()
  countSpec=$primaryCount
  # !! $primaryCount may already be $kIDCHAR_ENDLESS if specified as such by the user, but we also set it to $kIDCHAR_ENDLESS
  # !! here if $primaryCount represents the total byte size, in which case we want repeat() to produce endless output,
  # !! which we then limit via headChars to achieve the desired char. count.
  (( primaryCountIsChars )) && countSpec=$kIDCHAR_ENDLESS
  if (( randomWords )); then
    if (( lineBasedOutput )); then
      [[ -n perLineCountSpec ]] && countSpec+=",$perLineCountSpec"
    else # With words, we assume SINGLE-line output by default (even though the underlying source - the dictionary file - is line-based, but that's an implementation detail).
      # Translate the primary count, which getRandomLines() would interpret as line-based, into a column-based count spec.
      countSpec="1,$countSpec"
    fi
  else # randomLines
    # Lines from a file are by definition line-based, pass $primaryCount through as a line count.
    # !! For now, we don't expose getRandomLine()'s ability to place multiple input lines on a single output line.
    :
  fi

  cmdArgs=( getRandomLines -- "$countSpec" "$file" )

  if (( countBytesOnly )); then
    # Note that due to varying line lengths we must actually run the command to measure byte size.
    # Even if $primaryCountIsChars is true, we must run the command, as we cannot predict how
    # character count maps onto byte count without knowing how many and what multi-byte characters are in the randomly selected lines.
    byteCount=$(( $("${cmdArgs[@]}" | wc -c) )) # the extra $(( ... )) is to trim the leading whitespace that BSD wc outputs.
    (( ${PIPESTATUS[0]} == 0 )) || die
    echo "$byteCount"
    exit 0
  fi

  if (( primaryCountIsChars )); then
echo "[???]"    
    "${cmdArgs[@]}" | headChars $primaryCount
    # Make sure that head succeeded, and that seq either reported success
    # or 141 (128 + 13 (SIGPIPE)), which happens when head exits after having
    # received enough data.
    (( $? == 0 && (${PIPESTATUS[0]} == 0 || ${PIPESTATUS[0]} == 141) )) || die
  else # fixed-count or endless output
    "${cmdArgs[@]}" || { (( endless && $? == 141 )) || die; }
  fi

else # specified STATIC text
  
  # Determine the text to repeat
  if (( $# == 0 )); then # read from stdin - all input at once.
    IFS= read -d $'\x4' -r txt  # !! $'\x4' is required to support interactive (all-lines-at-once) input that can be terminated with ^D.
  else # all remaining operands (though typically only 1)
    txt=$*
  fi

  # Synthesize a  fully formatted repeat unit to pass to repeat() below.
  if (( lineBasedOutput )); then  # apply per-line repeat count: a unit is a full output line composed of repeated, possibly formatted input instances.
    # Synthesize a  fully formatted repeat unit in the form of 1 output line, including trailing \n (except with endless cols).
    case $perLineCount in
      0)
        unit=
        ;;
      *)
        if (( perLineCountIsChars )); then # fill line up to fixed / max. char. count
          instanceCount=$(( perLineCount / ${#txt} ))
          (( instanceCount * ${#txt} < perLineCount && perLineCharCountIsFixed )) && (( ++instanceCount ))
          unit=$(repeat "${repeatFmtOpts[@]}" -- $instanceCount "$txt")
          (( perLineCharCountIsFixed )) && unit=${unit:0:perLineCount}
        else
          # Create a line with $perLineCount instances, possibly formatted.
          # Note that with endless columns, only *1* instance is placed on the line - it'll be repeated indefinitely.
          unit=$(repeat "${repeatFmtOpts[@]}" -- $(( endlessSingleLine ? 1 : perLineCount )) "$txt")
        fi
        ;;
    esac
    if (( ! endlessSingleLine )); then
      unit+=$'\n' # add newline for line-based output
    fi
  else # single-line output: a unit is a single instance of the input, possibly formatted.
    # Synthesize a single, fully formatted repeat unit.
    unit=$(repeat "${repeatFmtOpts[@]}" -- 1 "$txt")
  fi

  # Calculate the length of 1 fully formatted repeat unit in bytes.
  unitByteCount=$(LC_ALL=C; printf %s "${#unit}") # !! In the *input*, we do *not* interpret backslash escape sequences.

  # Determine length of a separator in bytes and determine if separators even come into play to calculate the
  # byte length of the *effective* separator, which we need
  #  - to quickly calculate the total output byte count with -c, without having to generate the actual data.
  #  - to decide whether the more efficient single-byte repeat function, repeat_singleByte(), can be used.
  sepByteCount=$(LC_ALL=C; printf %b "${#sep}") # NOTE: We interpret backslash escape sequences in $sep, just as repeat() will.
  effectiveSepByteCount=0
  if (( sepByteCount > 0 )); then
    if (( lineBasedOutput )); then
      # Unless endless columns were requested, the separators are already built into $unit.
      (( endlessSingleLine )) && effectiveSepByteCount=$sepByteCount
    else # single-line output
      # With endless output or more than 1 unit, a separator is used.
      (( endless || primaryCount > 1 )) && effectiveSepByteCount=$sepByteCount
    fi
  fi
  # Determine what formatting options must be passed through to repeat() below:
  #  - either: none (for line-based output with finite columns; all formatting options were applied in synthesizing $unit) 
  #  - or: only the separator (for single-line output - whether with primary count only or via endless columns).
  if (( effectiveSepByteCount )); then
    repeatFmtOpts=( -s "$sep" )
  else
    repeatFmtOpts=()
  fi
  
  # If endless columns are specified, we must pass $kIDCHAR_ENDLESS to repeat_singleByte() and repeat() as the - one and only - count.
  if (( lineBased && endlessSingleLine )); then
    primaryCount=$kIDCHAR_ENDLESS
  fi

  # DRY RUN: only print the total count of bytes that *would* be generated and exit.
  if (( countBytesOnly )); then
    if (( primaryCountIsChars )); then
      echo "$primaryCount"
    else
      # Multiply unit size with the primary repeat count, taking separator instances, if any, into account.
      echo "$(( primaryCount * unitByteCount + (primaryCount - 1) * effectiveSepByteCount ))"
    fi
    exit 0
  fi

  # Invoke the implementing function - choose the most efficient one:
  if (( unitByteCount == 1 && effectiveSepByteCount == 0 )); then # SINGLE BYTE to repeat - for speed, use **Perl**, if available, else **head -c /dev/zero + tr**.

    repeat_singleByte $primaryCount "$txt" || { (( endless && $? == 141 )) || die; }
  
  else # MORE THAN 1 BYTE TO REPEAT AND/OR SEPARATOR/DELIMITER/TERMINATOR WAS SPECIFIED -> use **Perl**, if available, else **awk**.

      # !! $primaryCount may already be $kIDCHAR_ENDLESS if specified as such by the user, but we also set it to $kIDCHAR_ENDLESS
      # !! here if $primaryCount represents the total byte size, in which case we want repeat() to produce infinite output,
      # !! which we then limit via head -c to achieve the desired byte count.
    cmdArgs=( repeat "${repeatFmtOpts[@]}" -- $( (( primaryCountIsChars )) && printf %s $kIDCHAR_ENDLESS || printf %s $primaryCount ) "$unit" )

    if (( primaryCountIsChars )); then
      "${cmdArgs[@]}" | head -c $primaryCount
      # Make sure that head succeeded, and that seq either reported success
      # or 141 (128 + 13 (SIGPIPE)), which happens when head exits after having
      # received enough data.
      (( $? == 0 && (${PIPESTATUS[0]} == 0 || ${PIPESTATUS[0]} == 141) )) || die
    else # fixed-count or endless output
      "${cmdArgs[@]}" || { (( endless && $? == 141 )) || die; }  # With endless output, we don't consider termination with SIGPIPE an error.
    fi

  fi

fi
