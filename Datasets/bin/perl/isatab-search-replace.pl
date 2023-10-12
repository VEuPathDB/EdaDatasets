#!/usr/bin/env perl
#             -*- mode: cperl -*-
#

use strict;
use warnings;
use XML::LibXML;
use Getopt::Long;
use FindBin;
use Tie::File;
use File::Copy::Recursive qw(dircopy);

#
# usage:
#
#   ./isatab-search-replace.pl --studyName VBP0000123 --newVersion 2023-12-31 --search regexp --replace string
#
#
# USE WITH CARE - it is very crude - use word delimiters in the search pattern to avoid unexpected replacements, e.g.
#   --search '\bNCBITaxon_1234\b'
# won't match NCBITaxon_12345.
#
# options:
#
#   --datasets ../../lib/xml/datasets/VectorBase.xml : path to datasets.xml (relative to script location)
#   --manualDelivery /eupath/data/EuPathDB/manualDelivery/VectorBase/popbio : path to manualDelivery (this is the default)
#   --dry-run : will copy the directory (but will not clobber) and make the search/replace edits
#               but it won't update the datasets.xml file
#
# what does it do?
#
# 1. finds the <dataset> element in ./Datasets/lib/xml/datasets/VectorBase.xml with the requested studyName
# 2. uses the current version name in that element to locate the (parent of the) ISA-Tab directory in manualDelivery,
#    e.g. /eupath/data/EuPathDB/manualDelivery/VectorBase/popbio/<studyName>/2023-08-11
# 3. copies that directory recursively to /eupath/data/EuPathDB/manualDelivery/VectorBase/popbio/<studyName>/<newVersion>
# 4. applies a `s/search/replace/g` operation to all lines of all final/*.txt files in the new directory (no backup files made)
# 5. updates the version string for the dataset in the XML representation
# 6. outputs a new VectorBase.xml (not making a .old file - assuming file is under version control) (unless --dry-run)
#
# Note that this script seems to preserve character encodings just fine.
#

my $studyName;
my $newVersion;
my $search;
my $replace;
my $datasets_file = "$FindBin::Bin/../../lib/xml/datasets/VectorBase.xml";
my $manualDelivery_path = '/eupath/data/EuPathDB/manualDelivery/VectorBase/popbio';
my $dry_run;

GetOptions(
	   "datasets=s" => \$datasets_file,
	   "manualDelivery=s" => \$manualDelivery_path,
	   "studyName=s" => \$studyName,
	   "newVersion=s" => \$newVersion,
           "dry-run|dry_run" => \$dry_run,
	   "search=s" => \$search,
	   "replace=s" => \$replace,
           );

die "ERROR: must provide '--studyName VBP0000123' on commandline\n" unless ($studyName);
die "ERROR: must provide '--newVersion 2023-12-31' on commandline\n" unless ($newVersion);
die "ERROR: must provide '--search PATTERN --replace STRING on commandline\n" unless (defined $search && defined $replace);

# this forces empty XML tags to be rendered long-hand as `<tag attr="abc"></tag>`
# it is UNSUPPORTED in the current version and may not work for ever.
local $XML::LibXML::setTagCompression = 1;

# 0. open/parse the XML file
my $parser = XML::LibXML->new();
my $doc = $parser->parse_file($datasets_file);

# 1. find the <dataset> element for the requested studyName
my $dataset_element;
foreach my $element ($doc->findnodes(qq{//dataset[prop[\@name="studyName" and text()="$studyName"]]})) {
  $dataset_element = $element;
  last;
}
die "ERROR: couldn't find '$studyName' in '$datasets_file\n" unless $dataset_element;

# 2a get the previous version from here (shouldn't be more than one prop with this attribute)
my ($version_prop) = $dataset_element->findnodes('prop[@name="version"]');
my $oldVersion = $version_prop->textContent;

die "ERROR: old ($oldVersion) and new versions ($newVersion) can't be the same. Perhaps datasets.xml needs reverting.\n" if ($oldVersion eq $newVersion);

# 2b find ISA-Tab parent dir and confirm it's there
my $old_parent_dir = "$manualDelivery_path/$studyName/$oldVersion";
die "ERROR: directory '$old_parent_dir' not found" unless (-d $old_parent_dir);

# 3. copy it to the new location
my $new_parent_dir = "$manualDelivery_path/$studyName/$newVersion";
die "ERROR: ISA-Tab directory has already/previously been copied to '$new_parent_dir'.\nToo dangerous to proceed!\n" if (-d $new_parent_dir);

print "Copying $old_parent_dir to $new_parent_dir\n";
dircopy($old_parent_dir, $new_parent_dir) or die "ERROR: directory copy failed: $!";

# 4. do the search/replace
foreach my $file (glob($new_parent_dir."/final/*.txt")) {
  my $changes = 0;
  tie my @lines, 'Tie::File', $file or die "ERROR: can't open '$file' for search/replace\n";
  s/$search/$replace/g && $changes++ for @lines;
  untie @lines;
  printf "Made %5d replacements in $file\n", $changes;
}

# 5. set the new version
unless ($dry_run) {
  my $new_text_node = $doc->createTextNode($newVersion);
  # Replace existing child nodes with the new text node
  $version_prop->removeChildNodes();
  $version_prop->appendChild($new_text_node);
}

# 6. output the modified XML
unless ($dry_run) {
  open OUT, ">$datasets_file" || die "ERROR: can't write to '$datasets_file'\n";
  print OUT $doc->toString();
  close OUT;
  print "Wrote new $datasets_file.\nDon't forget to commit and push to github!\n";
}

