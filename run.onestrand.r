#!/usr/bin/Rscript

options(echo=TRUE)
args <- commandArgs(trailingOnly = TRUE)
print(args)

input.list = args[1]
cred.file = args[2]


#ec2 default settings
price = 3.0
realm = 'us-east-1'
region = paste0(realm,'d')

print('parse credential file')
cf=readLines(cred.file)
cf=cf[-grep('#',cf)]
for(sp in strsplit(cf,':')){
    print(sp)
    assign(sp[1],sp[2])
}
if(!file.exists(rsa_key)){print('check rsa key is readable')}
keyname=rev(strsplit(rsa_key,'[/.]')[[1]])[2]
print('setting key name to:')
print(keyname)

tmp = paste0(tempfile(),'.rsa')
file.copy(rsa_key,tmp)
Sys.chmod(tmp,mode='600')
rsa_key = tmp


#set up credentials
starcluster.rsa = rsa_key
#mailaddr = 'thashim@csail.mit.edu' # MAKE SURE THIS EMAIL IS SET UP ON AMAZON SES
key.name = key_name
access.key = access_key
secret.key = secret_key
bucket.name = bucket_name
#'cgs-kmer-model'

system('mkdir /.aws')
system(paste0('printf \"[default]\naws_access_key_id=',access_key,'\naws_secret_access_key=',secret_key,'\" > /.aws/config'))

############
# default parameters (can be overwirtten in .list files

#organism specific
genome='hg19'

#runtime params
maxk=8
k=200
resol=1

#runtime params (used)
read.max=50
smooth.window=1
require('utils')
cov.num = 0
upb = 20
mbsize = 40960000

#probably dont need changing..
branch = 'no91'

source('/kmm/run.cluster.onestrand.r')
