# hardcoded directories
gbase = '/genome/'


### load input
input.lines=readLines(input.list)
input.lines=input.lines[nchar(input.lines)>0]
input.options=input.lines[grep('#',input.lines)]
bam.prefix=''
out.prefix=''
postfix=''

epointers = (1:length(input.lines))[-grep('#|//',input.lines)]
ep2 = c(0,epointers)

############
# functions

rsystem <- function(sh,intern=F,wait=T){
    system(paste0('ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ',starcluster.rsa,' ubuntu@',INSTANCE_NAME,' ',shQuote(sh)),intern=intern,wait=wait)
}

scptoclus <- function(infile,out,intern=F){
    system(paste0('scp -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' ',shQuote(infile),' ubuntu@',INSTANCE_NAME,':',shQuote(out)))
}

scpstring <- function(infile,out,intern=F){
    paste0('scp -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' ',shQuote(infile),' ubuntu@',INSTANCE_NAME,':',shQuote(out))
}

scpfromclus <- function(infile,out,intern=F){
    system(paste0('scp -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -c arcfour -i ',starcluster.rsa,' -r ubuntu@',INSTANCE_NAME,':',shQuote(infile),' ',shQuote(out)))
}

getFilename<-function(x){
    rev(strsplit(x,'/')[[1]])[1]
}

############
# script


for( i in 1:length(epointers) ) {
    t1=Sys.time()

    if(epointers[i] > (ep2[i]+1)){
        for(option in (ep2[i]+1):(epointers[i]-1)){
            ss=strsplit(input.lines[option],'[# ]')[[1]]
            ss=ss[nchar(ss)>0]
            print(paste0('set:',ss[1],' to:',ss[2]))
            assign(ss[1],ss[2])
        }
    }
    #
    input.bams = input.lines[epointers[i]]
    rl = strsplit(input.bams,'[,]')[[1]]
    exptname = rl[1]
    bamlist = rl[-1]
    print('Starting experiment:')
    print(exptname)
    print(bamlist)

    #organism specific config
    genomedir=paste0(gbase,genome,'.in')
    offset.file = paste0(gbase,genome,'.offsets.txt')
    chroffs = as.double(readLines(offset.file))
    chr.name = as.character(1:(length(chroffs)-1))
    #
    trainchr = which(chroffs > 2^31)[1]-1
    testchr = which(chroffs > 2^31)[1]
    #do NOT exceed 2147483647 (2^31-1), chr9 human is 1680373143
    train.bases = min( chroffs[trainchr + 1], 2^31 - 1)
    #heldout is chr18, this is the start of chr18 in your organism
    heldout.start= chroffs[trainchr + 1]
    #default 90702639 is the size of chr18 in mouse, keep it smaller than this number
    test.bases = chroffs[testchr + 1] - heldout.start

    #launch instance
    userdatablob=paste0(system('cat /kmm/user-data.txt | base64',intern=T),collapse='')
    ami='ami-35dbde5c'
    lspec = paste0("\'{\"UserData\":\"",userdatablob,"\",\"ImageId\":\"",ami,"\",\"KeyName\":\"",keyname,"\",\"InstanceType\":\"c3.8xlarge\"}\'")
    launch=system(paste0('aws --region ',realm,' --output text ec2 request-spot-instances --spot-price ',price,' --launch-specification ',lspec),intern=T)

    sirname = strsplit(launch,'\t')[[1]][4]
    sistatus = ''

    #####
    # process bam while we wait..

    tmpdir = paste0('/tmp/kmer-',sirname,'/')
    unlink(tmpdir,T,T)
    dir.create(tmpdir)

    for(bamfile in bamlist){
        if(!file.exists(paste0(bam.prefix,bamfile,'.bai'))){
            print("No bam index found, reindexing")
            x=paste0(bam.prefix,bamfile)
            y=paste0("samtools index ",shQuote(x))
            print(y)
            system(y,wait=T)
        }
    }

    print('Extracing reads from bam file')
    dir.create(paste0(tmpdir,exptname),F)
    unlink(paste0(tmpdir,exptname,'/*'),T,T)

    for(bamfile in bamlist){
        print(bamfile)
        clist = sapply(1:length(chr.name),function(chr){
            paste0("(samtools view -F 788 -q ",quality," ",shQuote(paste0(bam.prefix,bamfile))," chr",chr.name[chr]," | cut -f 4 >> \'",tmpdir,exptname,"/allreads-",chr,".csv\'; touch ",tmpdir,exptname,"/chr",chr,".done)")
        })
        writeLines(clist,paste0(tmpdir,'commlist.txt'))
        system(paste0('cat ',tmpdir,'commlist.txt | parallel --progress'))
    }

    chrin = testchr
    readsin=scan(paste0(tmpdir,exptname,'/allreads-',chrin,'.csv'),list(0))
    rrle=rle(sort(readsin[[1]]))
    rcoord=rrle$value
    rnum=rrle$length
    rbequiv=rep(0,test.bases)
    print(max(rcoord))
    rbequiv[rcoord[rcoord<test.bases]]=rnum[rcoord<test.bases]

    con=file(paste0(tmpdir,exptname,'/heldout.in'),'wb')
    writeBin(rbequiv,con,4)
    close(con)

    #####
    # check if spot is up

    print('wait for spot fulfilment')
    while(sistatus!='fulfilled'){
        cat('.')
        sitest=system(paste0('aws --region ',realm,' --output text ec2 describe-spot-instance-requests --spot-instance-request-ids ',sirname),intern=T)
        sistatus=strsplit(sitest,'\t')[[grep('STATUS',sitest)]][2]
    }
    iname = strsplit(sitest,'\t')[[1]][3]

    rname=paste0(exptname,postfix)
    system(paste0('aws --region ',realm,' --output text ec2 create-tags --resources ',iname,' --tags Key=Name,Value=',rname))

    istatus = 'initializing'

checks.passed = 0

    print('wait for status checks')
    while(checks.passed < 2){
        cat('.')
        itest=system(paste0('aws --region ',realm,' --output text ec2 describe-instance-status --instance-ids ',iname),intern=T)
        if(length(itest)>=3){
            checks.passed = length(grep('passed',itest))
        }
    }

    istat=system(paste0('aws --region ',realm,' --output text ec2 describe-instances --instance-ids ',iname),intern=T)

    INSTANCE_NAME = strsplit(istat,'\t')[[grep('INSTANCES',istat)]][16]

    while(length(grep('done',rsystem('ls /mnt',intern=T)))==0) { Sys.sleep(5) }

    scptoclus(genomedir,'/mnt/input/genome.in')

    read.options=paste0(
        '--num_chr=',rev(chr.name)[1],' ',
        '--num_bases=',rev(chroffs)[1],' ',
        '--max_ct=100 ',
        '--offsets_file=/mnt/input/offsets.txt ',
        '--out_file=/mnt/input/reads.in')

    clist=sapply(1:(length(chr.name)),function(chr){
        scpstring(paste0(tmpdir,exptname,'/allreads-',chr,'.csv'),'/mnt/input/')
    })
    writeLines(clist,paste0(tmpdir,'commlist.txt'))
    system(paste0('cat ',tmpdir,'commlist.txt | parallel --progress -j 4'))

    scptoclus(offset.file,'/mnt/input/offsets.txt')

    scptoclus(paste0(tmpdir,exptname,'/heldout.in'),'/mnt/input/heldout.in')

    while(length(grep('setup',rsystem('ls /home/ubuntu/',intern=T)))==0) {
        Sys.sleep(5)
    }

    unlink(tmpdir,T,T)

### run
    rsystem('git clone https://thashim-ro:*SybT2X9@bitbucket.org/thashim/delete_later.git /home/ubuntu/delete_later')
    rsystem('mkdir /home/ubuntu/delete_later/build')
    rsystem('rm -rf ~/delete_later/build/*')
    rsystem(paste0('cd ~/delete_later/; git pull; git checkout ',branch))
    cmakestr = paste0('-DK=',k,' -DRESOL=',resol,' -DKBIG=',maxk,' -DMINIBATCH=',mbsize)
    rsystem(paste0('cd ~/delete_later/build/; cmake .. ; make clean; make -j CXX_DEFINES=\"',cmakestr,'\"'))
                                        #make reads
    readstr=paste0('cd ~/delete_later/build/; ./reads ',read.options,' --reads_dir=/mnt/input/')

    scptoclus(input.list,'~/input.list')
    rsystem(paste0('printf \'',paste0('i=',i,'\n'),'\' > ~/params.txt'));

                                        #enable credentials remotely
    rsystem('mkdir ~/.aws')
    rsystem(paste0('printf \"[default]\naws_access_key_id=',access.key,'\naws_secret_access_key=',secret.key,'\" > ~/.aws/config'))

    runstr=paste0('~/delete_later/build/mpi_motif --out_dir=/mnt/output --genome=/mnt/input/genome.in --reads=/mnt/input/reads.in --num_bases=',train.bases,' --read_max=',read.max,' --smooth_window_size=',smooth.window,' --heldout_start=',heldout.start,' --heldout_size=',test.bases,' --heldout_reads=/mnt/input/heldout.in 2>&1 | tee /home/ubuntu/runlog.txt')

    rl=readLines('/kmm/standalone.template.txt')
    rname=paste0(exptname,postfix)
    rl=gsub('READ_STR',readstr,rl)
    rl=gsub('RUN_NAME',rname,rl)
    rl=gsub('REGION',realm,rl)
    rl=gsub('SIRNAME',sirname,rl)
    rl=gsub('INAME',iname,rl)
    rl=gsub('EMAIL',mailaddr,rl)
    rl=gsub('RUN_STR',runstr,rl)
    rl=gsub('TEST_CHR',testchr,rl)
    rl=gsub('BUCKET_NAME',bucket.name,rl)

    rsystem(paste0('printf \'',paste0(rl,collapse='\n'),'\' > ~/runall.sh'))
    rsystem('chmod +x ~/runall.sh')
    rsystem('nohup ~/runall.sh `</dev/null` >nohup.txt 2>&1 &')
    print('Launch finished in:')
    print(Sys.time()-t1)
}
