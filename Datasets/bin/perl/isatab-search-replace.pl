#!/usr/bin/env perl

use strict;
use warnings;
use XML::LibXML;
use Getopt::Long;
use FindBin;

use File::Copy::Recursive qw(dircopy);

#
# usage:
#
#   ./isatab-search-replace.pl --studyName VBP0000123 --newVersion 2023-12-31 --search regexp --replace string
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
# 4. applies the search/replace operation to all files in the new directory
# 5. updates the version string for the dataset in the XML representation
# 6. outputs a new VectorBase.xml (and backs up the old one to VectorBase.xml.old) (unless --dry-run)

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
           );

die "ERROR: must provide '--studyName VBP0000123' on commandline\n" unless ($studyName);
die "ERROR: must provide '--newVersion 2023-12-31' on commandline\n" unless ($newVersion);

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

# 2b find ISA-Tab parent dir and confirm it's there

my $old_parent_dir = "$manualDelivery_path/$studyName/$oldVersion";
die "ERROR: directory '$old_parent_dir' not found" unless (-d $old_parent_dir);

# 3. copy it to the new location
my $new_parent_dir = "$manualDelivery_path/$studyName/$newVersion";

die "ERROR: ISA-Tab directory has already/previously been copied to '$new_parent_dir'.\nToo dangerous to proceed!\n" if (-d $new_parent_dir);

dircopy($old_parent_dir, $new_parent_dir) or die "ERROR: directory copy failed: $!";

# 4. do the search/replace

# TO DO!

# 5. set the new version

unless ($dry_run) {
  my $new_text_node = $doc->createTextNode($newVersion);
  # Replace existing child nodes with the new text node
  $version_prop->removeChildNodes();
  $version_prop->appendChild($new_text_node);
}

# 6. output the modified XML

unless ($dry_run) {
  # to do - write to file and back up original
  # print $doc->toString();
}

