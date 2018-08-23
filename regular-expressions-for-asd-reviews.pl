#!/usr/bin/env perl

use strict;
use DBI;
use Lingua::Sentence;
use Lingua::EN::Tagger qw(add_tags);
use HTML::Restrict;
use Data::Dumper;

use constant ASD          => "(asd|aspergers|aspie|autie|autistic|autism|on the spectrum)";
use constant HELPS        => "(gets (so)? much out of it|helps|helped|assists|enables|engages)";
use constant LIKES        => "(obesse(s|ed)|like(s|ed)|love(s|d)|interest(ed|s)|appeal(s|ing))";
use constant RELATIONSHIP => "(boy|girl|[0-9] *yearold|toddler|twins|[0-9] *yr|caregiver|kid|preschooler|school|" .
                             "year old|[0-9] *y.o.|[0-9 ] *yo|my little one|I(m| am| have| suffer)|famil(ies|y)|" .
                             "child|children|(god|grand)(son|daughter)|teen|adult|cuz|cousin|bro|brother|sis|" .
                             "sister|son|daughter|niece|nephew|brother|sister|mother|father|student|classroom)";

use constant EVIDENCE_BASED => "(evidence( |-)based)|(research( |-)based)|developed|consulted|professional|pathologist|therapist";

# Specific ASD Information
use constant FEEDBACK     => "(feedback|results|graph|answers|response)";
use constant MOTIVATION   => "(encourages|helps|incentive)";

use constant CUSTOM       => "(customi(s|z)ation|custom|changing|adapting|personali(s|z)ation|personali(s|z)e)";
use constant INDEPENDENCE => "(by (him|her)self|on (his|her) own|independent|independence|victory|triumph)";
use constant TRIAL        => "(part of a clinical trial)";

# Helps With --------
use constant HYGIENE     => "(wash(ing)? hands|brush(ing)? (teeth)?|potty|toilet)";
use constant BEHAVIOR    => "(compliant|calm down|meltdown|emotion|tantrum|attention|behavior|behaved)";
use constant TRACKER     => "(monitor|tracker|track|diary|log)";
use constant LANGUAGE    => "(augmentative communication|words|(sounds|sound) out|language|speak|speaking|talk|speech|" .
                            "aac|picture exchange|words|communicating|communicate|pecs|communication|vocabulary)";
                            
use constant EDUCATION   => "((match|matching) (shapes|learning|objects|items|colors)|concepts|animals|alphabet|education|" . 
                            "colors|count|colours|learning|spelling|maths|letters|arithmetic|multiplication|addition|" . 
                            "mathematics|numbers|reading|read|grammar|history|" .
                            "english|books|maths|sentence)";
use constant ATTENTION   => "(engage(s|d)|focuse(d|s)|keeps (his|her) focus|concentration|attention|focus)";
use constant MOTOR       => "((fine|gross)? motor|coordination|hand eye coordination|motor skills)";
use constant FOOD        => "(eating|eats|food|eaten|diet)";
use constant IMAGINATION => "(writing|imagine|visualize|creating|visualise|story sequencing|imagining|imagination|story telling|comics)";
use constant SENSORY     => "(block(s)? (out)? (external|outside)? noise(s)?|visual|sensor|sensory|music|sound|image|touch|" . 
                            "haptic|backgrounds distracting)";
use constant EYE_CONTACT => "(eye contact)";
use constant SOCIAL      => "(interact|social|social(ize|ise)|friend(s)?|participate|join in)";
use constant SLEEP       => "(sleep|bedtime|nap|bed time)";
use constant EMOTION     => "(feelings|calm down|anxieties|anxiety|decrease(s)? (stress(ful)?|anger|depression|sadness|" . 
                            "anxiety)|control(s)? (his|her)? emotion(s)?|clear (his|her) mind)";

# Bad Reviews
use constant ADS         => "(ads|advertisement)";
use constant COST        => "(price|cost|(waste of|not worth) (the)? money|ripped off|expensive| (can not|can t|cant) (afford|pricey))";
use constant FUNCTION    => "((isn t|is not) (opening|working)|broken|bugs|needs fixing|frozen|freezes|confusing|crash(es)?|" . 
                            "crashed|shuts off|bad design|not user friendly)";
use constant CONSIST     => "(drama|frustrat(ion|ed)|tantrum(s)?|scream(s|ing))";

use constant MONTHS => "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)";
use constant YEARS => "(2008|2009|2010|2011|2012|2013|2014|2015|2016)";

sub st # Speech Tagger
{
    my $postagger = new Lingua::EN::Tagger;
    my $tag = $postagger->add_tags($_[0]);
    return  $tag;
}

sub sp  # splits sentence 
{
    my $splitter = Lingua::Sentence->new("en");
    my $text = $_[0];
    my $res =  $splitter->split($text);
    my @t   =  split /\n/, $res;
    return @t;
}

sub openDatabase
{
    # define database name and driver
    my $driver   = "SQLite";
    my $db_name = $_[0]; # Database name
    my $dbd = "DBI:$driver:dbname=$db_name";
  
    # sqlite does not have a notion of username/password
    my $username = "";
    my $password = "";

    print STDERR "Openning $db_name\n";   
    
    # create and connect to the database.
    my $dbh = DBI->connect($dbd, $username, $password, { RaiseError => 0 }) or die $DBI::errstr;
    print STDERR "Database opened successfully\n";
    return $dbh
}

sub wc # word count
{
    my $str = shift;
    return 1 + ($str =~ tr{ }{ });
}

sub findApps
{
    my $hr = HTML::Restrict->new(); # Removes unwanted HTML
    my $dbh = $_[0]; # Database handler
    my $dbn = $_[1]; # Databasename 
    my $stmt = ($dbn =~ m/apple/)  ? 
        qq(SELECT AppleID, Description,Price, HasInAppPurchases from Details;) :
        qq(SELECT AppID, Long, Hash, Price, InAppPurchases from Details;);
 
    my $obj = $dbh->prepare($stmt);
    my $ret = $obj->execute() or die $DBI::errstr;
    my %apps;

     while(my @row = $obj->fetchrow_array()) {
        my $appID   = $row[0];
        my $des     = $row[1];
        my $price   = $row[2];
        my $inapp   = $row[3];
        my $hash    = $appID . $des;
    

        $des = $hr->process($des);
        $des  =~ s/[^[a-zA-Z0-9 -!.$]]//g;

        my $keywords = ASD;
        if ($des =~ /\b$keywords\b/i) { # Match words and be case insensitive
            $apps{$appID} = $des . "|" . $price . "|" . $inapp;  
        }
    }
    my $size = keys %apps;
    print "Found " . $size . " apps" . "\n";
    return %apps;
}

sub findEvidenceBased
{
    my ($dbh, $dbn) = @_;
    my %apps = findApps($dbh, $dbn);
    my %eb;

    foreach my $key (keys %apps) {
        my $app = $apps{$key}; 
        $eb{$key} = $app if match($app, EVIDENCE_BASED);
        
    }
    return %eb;
}

sub printHashSize
{
    my %hash = @_;
    my $size = keys %hash;
    print "Hash Size " . $size . "\n";
}

sub findReviews_forApps # Finds the reviews only for apps given
{
    my ($dbh, $dbn, %apps) = @_;
    my %reviews = findReviews($dbh, $dbn);
    my %filtered;

    foreach my $key (keys %reviews) {
        my ($appID, $title, $body, $rating) = split(/\|/, $reviews{$key});
        $filtered{$key} = $reviews{$key} if exists $apps{$appID};
    }

    printHashSize(%filtered);
    return %filtered;
}

sub findReviews_ByAuthor
{
    my $dbh = $_[0]; # Database handler
    my $dbn = $_[1]; # Databasename
    my $aut = $_[2]; 

    my $stmt = $dbn eq "apple.db"  ? 
        qq(SELECT AppleID, Subject,Body,Hash,Rating,Date,AuthorID from Reviews;) :
        qq(SELECT AppID, ReviewTitle, Comments, Hash, Rating,Date,UserName from Reviews;);
    
    my $obj = $dbh->prepare($stmt);
    my $ret = $obj->execute() or die $DBI::errstr;
    my %appData;
   
    while(my @row = $obj->fetchrow_array()) {
        my $appID   =    $row[0];
        my $title   = lc $row[1];
        my $body    = lc $row[2];
        my $hash    =    $row[3];
        my $rating  =    $row[4];
        my $date    =    $row[5];
        my $authid  =    $row[6];
        

        $title =~ s/[^[a-zA-Z0-9 !.$]]//g;
        $body  =~ s/[^[a-zA-Z0-9 !.$]]//g;

        my $keywords = ASD;
        if ($authid eq $aut) { # Match words and be case insensitive
        
            $keywords = RELATIONSHIP;
            my $data= $appID . "|" . $title . "|" . $body . "|" . $rating . "|" . $date . "|" . $authid;
            
            if ($body =~ /\b$keywords\b/i) {
                next if wc($body) < 3;
                $appData{$hash} = $data; 
                # print $date . "\n"; 
            } else {
                #print $data;
            }
        }
    }
    return %appData;
} 



sub findReviews
{
    my $dbh = $_[0]; # Database handler
    my $dbn = $_[1]; # Databasename 
    my $stmt = $dbn eq "apple.db"  ? 
        qq(SELECT AppleID, Subject,Body,Hash,Rating,Date,AuthorID from Reviews;) :
        qq(SELECT AppID, ReviewTitle, Comments, Hash, Rating,Date,UserName from Reviews;);
    
    my $obj = $dbh->prepare($stmt);
    my $ret = $obj->execute() or die $DBI::errstr;
    my %appData;
   
    while(my @row = $obj->fetchrow_array()) {
        my $appID   =    $row[0];
        my $title   = lc $row[1];
        my $body    = lc $row[2];
        my $hash    =    $row[3];
        my $rating  =    $row[4];
        my $date    =    $row[5];
        my $authid  =    $row[6];
        

        $title =~ s/[^[a-zA-Z0-9 !.$]]//g;
        $body  =~ s/[^[a-zA-Z0-9 !.$]]//g;

        my $keywords = ASD;
        if ($body =~ /\b$keywords/i) { # Match words and be case insensitive
        
            $keywords = RELATIONSHIP;
            my $data= $appID . "|" . $title . "|" . $body . "|" . $rating . "|" . $date . "|" . $authid;
            
            if ($body =~ /\b$keywords\b/i) {
                next if wc($body) < 3;
                $appData{$hash} = $data; 
                # print $date . "\n"; 
            } else {
                #print $data;
            }
        }
    }
    return %appData;
} 

sub printRatings 
{
    my %data = @_;
    foreach my $key (keys %data) { 
        my $row = $data{$key};
        my @t   =  split /\|/, $row;
        print $t[3];
    }
}

sub dates 
{
    my %data = @_;
    my %years;
    foreach my $key (keys %data) { 
        my $review = $data{$key};
        my ($id, $title, $body, $rating, $date)  = split(/\|/, $review);
        
        my $regx = YEARS;
        if ($date =~ /$regx/i) {
            my $ye = $1; 
            $regx = MONTHS; 
            if ($date =~ /$regx/i) { 
                my $mo = $1;
                my $key =  "01/" . $mo . "/" . $ye;
                $years{$key}++;
            }
        }
   }
   return %years;
}


sub badReviews
{
    my ($max, %data) = @_;
    my %bad;
    my $cnt = 0;
    
    foreach my $key ( keys %data ) {
            
           my $review = $data{$key};
           my ($id, $title, $body, $rating)  = split(/\|/, $review);
        
           if ($rating le $max) {
                $cnt++;
                #print $review . " -> " . $rating . "->" . $max . "\n";       
                $bad{"ADS"}++      if match($review, ADS);
                $bad{"CONSIST"}++  if match($review, FUNCTION) && match($review, CONSIST);
                $bad{"COST"}++     if match($review, COST);
                $bad{"FUNCTION"}++ if match($review, FUNCTION); 
           }  
    }
    print STDERR "Found " . $cnt . "\n";
    return %bad; 
}

sub printBody 
{
    my %data = @_;
    foreach my $key (keys %data) {
        my $row = $data{$key};
        my @t   =  split /\|/, $row;
        print $t[2];
    }
}

sub match
{
    my $line = $_[0];
    my $regx = $_[1];
    return $line =~ /\b$regx\b/i;
}

sub helpsWith
{
    my %data = @_;
    my $size = keys %data;
    
    my %helps;
    my $cnt = 0; 
    foreach my $key ( keys %data ) {
        my $in = $data{$key};
        my $review = $in;  
        my $regx = HELPS;
        
        if ($review =~ /$regx/i) { 
           $cnt++;

           $review = substr($review, $-[0]);
          
           $helps{"SOCIAL"}++      if match($review, SOCIAL);
           $helps{"SLEEP"}++       if match($review, SLEEP);
           $helps{"HYGIENE"}++     if match($review, HYGIENE);
           $helps{"BEHAVIOR"}++    if match($review, BEHAVIOR); 
           $helps{"TRACKER"}++     if match($review, TRACKER);
           $helps{"LANGUAGE"}++    if match($review, LANGUAGE);
           $helps{"EDUCATION"}++   if match($review, EDUCATION); 
           $helps{"ATTENTION"}++   if match($review, ATTENTION);
           $helps{"MOTOR"}++       if match($review, MOTOR);
           $helps{"FOOD"}++        if match($review, FOOD); 
           $helps{"IMAGINATION"}++ if match($review, IMAGINATION);
           $helps{"SENSORY"}++     if match($review, SENSORY);
           $helps{"EYE_CONTACT"}++ if match($review, EYE_CONTACT);
           $helps{"EMOTION"}++     if match($review, EMOTION);
       }
    }
    print STDERR "Found " . $cnt . "\n";
    return %helps; 
}

sub main
{
    my $dbn = $ARGV[0];
    my $dbh = openDatabase($dbn);
    
    # my %data = findReviews($dbh, $dbn);

    #my %data = findReviews_ByAuthor($dbh, $dbn, "184066223");


    #my %reviews = findReviews($dbh, $dbn);
    #my %data  = dates(%reviews);

    #my %data = badReviews(5, %reviews);
    #my %data = helpsWith(%reviews);
 
    my %data = findEvidenceBased($dbh, $dbn);

    #my %apps = findApps($dbh, $dbn);
    #my %data = findReviews_forApps($dbh, $dbn, %apps);
    #   %data = helpsWith(%data);
    

    my @keys = keys %data;
    for my $key (@keys) {
        print $key . "|" .  $data{$key}. "\n";
    }
    my $size = keys %data; 
    #print "Size: " . $size . "\n";

   $dbh->disconnect();
}

# MAIN ENTRY
main();
