#!/bin/bash

#utilties for reading shim disk images

extract_initramfs() {
  local kernel_bin="$1"
  local working_dir="$2"
  local output_dir="$3"

  #first stage
  local kernel_file="$(basename $kernel_bin)"
  local binwalk_out=$(binwalk --extract $kernel_bin --directory=$working_dir --run-as=root)
  local stage1_file=$(echo $binwalk_out | pcregrep -o1 "\d+\s+0x([0-9A-F]+)\s+gzip compressed data")
  local stage1_dir="$working_dir/_$kernel_file.extracted"
  local stage1_path="$stage1_dir/$stage1_file"
  
  #second stage
  binwalk --extract $stage1_path --directory=$stage1_dir --run-as=root > /dev/null
  local stage2_dir="$stage1_dir/_$stage1_file.extracted/"
  local cpio_file=$(file $stage2_dir/* | pcregrep -o1 "([0-9A-F]+):\s+ASCII cpio archive")
  local cpio_path="$stage2_dir/$cpio_file"

  rm -rf $output_dir
  cat $cpio_path | cpio -D $output_dir -imd --quiet
}
