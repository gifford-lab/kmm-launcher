
A set of ec2 support scripts for the kmer-model which takes a bam and automatically generates fitted output to be placed into amazon's S3 storage system


##Example

Run the command in the git repo root:

```
docker pull thashim/kmm-launcher
docker run --rm -w `pwd` -v /cluster:/cluster -i thashim/kmm-launcher /kmm/run.onestrand.r  example/nrf.list /cluster/ec2/auth.txt
```

##Configuring the KMM

### auth.txt
```
realm:us-east-1
price:3.0
region:us-east-1d
rsa_key:/cluster/ec2/starcluster.rsa
access_key:REDACTED
secret_key:REDACTED
key_name:starcluster
bucket_name:kmer_rc2
mailaddr:thashim@csail.mit.edu
```

Useful options: 
`price` sets the max bid price, $3 is reasonable. Set too low and your jobs will get killed before completed

`region` sets the job submit regions, you can check the spot prices of a `c3.8xlarge` and pick a cheap region

`mailaddr` sets the email address that gets emailed at the end of a job. The emails will probably get spam-boxed first, so check spam folder.

Optional options:
`itype` sets the instance type: valid alternatives are cc2.8xlarge, to use this you must also change the AMI.

`ami` sets the AMI type: you will want to use the HVM image (`ami-864d84ee`) if you use any other instances like cc2.8xlarge or r3.8xlarge.

### *.list 

Example is available in git, some more are avaialable at /cluster/projects/wordfinder/paper/rlist

Example:
```
#bam.prefix /cluster/projects/wordfinder/bams/
#gbase /cluster/projects/wordfinder/data/genome/
#quality 0
#postfix .nrf_rc1
#bucket_name batch_runs
#maxk 8
#k 1000
#resol 4
#read.max 5
#smooth.window 20
#genome mm10

nrf_wt,nrf_round1/sherwood nodox Nrf1 test 1.bwa.mm10.bam,nrf_round1/sherwood plusdox Nrf1 test 1.bwa.mm10.bam,nrf_round1/sherwood sr3 Nrf1 test 1.bwa.mm10.bam,nrf_round1/sherwood sr8 Nrf1 test 1.bwa.mm10.bam

#smooth.window 10
#quality 20
dnase_1,mes_dnase/D0_175-400_130801.bwa.mm10.bam,mes_dnase/D0_50-100_130801.bwa.mm10.bam
```
Nearly all options can be overridden in a .list file.

The general format of a .list file is
```
#variable_name1 value
#variable_name2 value
[...]

experiment_name,bam_1.bam,bam_2.bam [..]

#variable_name1 value
[...]
experiment_name_2,bam_1 [...]
```

The launcher parses from top to bottom, setting each variable_name to value. Whenever it encounters a line without a `#` character, it will launch a KMM-job, assuming that the first entry is the experiment name and any following it are bams.

Later variable assignment lines starting with `#` will override earlier ones. In the example above, `nrf_wt` launches with a `quality` parameter of 0, but `dnase_1` is launched with `quality` of 20 due to the later override line.

#### Common arguments

`bam_prefix`: the path to where bam files are stored. Launcher will look for `bam_prefix+bam_name` where `bam_name` is the name in the `experiment_name`. 

`gbase`: path to where genome files are stored. do not change if run within gifford lab.

`quality`: mapper quality cutoff, pick q=0 by default, q=20 if attempting to avoid repeat regions and other hard-to-map regions.

`postfix`: postfix applied to jobs. Each job will go into a S3 bucket where they are separated into folders named `experiment_name+postfix`

`bucket_name`: s3 bucket name. This should generally be your username / project name to avoid mixing multiple people's jobs. 

`genome`: set to the organism genome. Currently only hg19 and mm10 are supported.

#### Tweakable parameters

`maxk`: Maximum kmer length to consider, 8 is generally good enough and the start of diminishing returns.

`k`: the window size. The model looks within a `[-k,+k]` region around each Kmer match. Should be a multiple of RESOL.

`read.max`: truncate input at read.max to avoid giant read-spikes from affecting model. Generally 5-10 is good for experiments in the < 1 billion read range


`resol`: the resolution at which parameters are stored. for example, if K=1000, RESOL=5, then the model fits 200 paremters, each representing 5 bases. **RESOL MUST BE ABLE TO DIVIDE K**

`smooth.window`: smooth the input by this many bases before feeding into the model. Useful for low-coverage experiments. Default of 10-20 is fine for all but extreme high or low coverage experiments.

`mbsize`: optimizer minibatch size, smaller is faster but less stable. Generally set to around 40960000 - 10240000. Most likely best not to touch this.

