#!/usr/bin/env bash

# wujian@2018

set -eu

nj=40
cmd="run.pl"

numpy=false
transpose=false
keep_length=false
fs=16000
stft_conf=conf/stft.conf

echo "$0 $@"

function usage {
  echo "Options:"
  echo "  --nj            <nj>                # number of jobs to run parallel, (default=40)"
  echo "  --cmd           <run.pl|queue.pl>   # how to run jobs, (default=run.pl)"
  echo "  --stft-conf     <stft-conf>         # stft configurations files, (default=conf/stft.conf)"
  echo "  --numpy         <numpy>             # load masks from np.ndarray instead, (default=false)"
  echo "  --transpose     <transpose>         # transpose TF-mask or not, (default=false)"
  echo "  --fs            <fs>                # sample frequency for output wave, (default=16000)"
  echo "  --keep-length   <true|false>        # keep same length as original or not, (default=false)"
}

. ./path.sh
. ./utils/parse_options.sh || exit 1

[ $# -ne 3 ] && echo "Script format error: $0 <wav-scp> <mask-dir/mask-scp> <enhan-dir>" && usage && exit 1

wav_scp=$1
enhan_dir=$3

for x in $wav_scp $stft_conf; do [ ! -f $x ] && echo "$0: missing file: $x" && exit 1; done

dirname=$(basename $enhan_dir)
exp_dir=exp/tf_masking/$dirname && mkdir -p $exp_dir

# if numpy=true, prepare mask.scp first
if $numpy; then
  [ ! -d $2 ] && echo "$0: $2 is expected to be directory" && exit 1
  find $2 -name "*.npy" | awk -F '/' '{printf("%s\t%s\n", $NF, $0)}' | \
    sed 's:\.npy::' | sort -k1 > $exp_dir/masks.scp
  echo "$0: Got $(cat $exp_dir/masks.scp | wc -l) numpy's masks"
else
  [ -d $2 ] && echo "$0: $2 is a directory, expected .scp" && exit 1
  cp $2 $exp_dir/masks.scp
fi

awk '{print $1}' $exp_dir/masks.scp | ./utils/filter_scp.pl -f 1 - $wav_scp | sort -k1 > $exp_dir/wav.scp
echo "$0: Reduce $(cat $wav_scp | wc -l) utterances to $(cat $exp_dir/wav.scp | wc -l)"

split_wav_scp=""
for n in $(seq $nj); do split_wav_scp="$split_wav_scp $exp_dir/wav.$n.scp"; done

./utils/split_scp.pl $wav_scp $split_wav_scp || exit 1

masking_opts=$(cat $stft_conf | xargs)
$numpy && masking_opts="$masking_opts --numpy"
$transpose && masking_opts="$masking_opts --transpose-mask"
$keep_length && masking_opts="$masking_opts --keep-length"

mkdir -p $enhan_dir
$cmd JOB=1:$nj $exp_dir/log/wav_separate.JOB.scp \
  ./scripts/sptk/wav_separate.py \
  --sample-frequency $fs \
  $masking_opts \
  $exp_dir/wav.JOB.scp \
  $exp_dir/masks.scp \
  $enhan_dir 

echo "$0: Run TF-masking done"
