# Importing required packages
import os
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import glob
import numpy as np
plt.rc('axes', labelsize=15)
plt.rc('xtick', labelsize=15)
plt.rc('ytick', labelsize=15)


# setting path relative to project structure
PROJECT_PATH = os.path.abspath('../')

# path to code executed by this snakefile
CODE_PATH = PROJECT_PATH + '/codes'

# path to reference files (genome, primers) required for trimming, alignement etc.
REF = PROJECT_PATH + '/ref/Bavtpat1_complete.fa'
PRIMERS = PROJECT_PATH + '/ref/primers.txt'

# path to raw sequencing data with automatic extraction of samplenames
R1 = PROJECT_PATH + '/data/{SAMPLENAME}_1.fastq'
R2 = PROJECT_PATH + '/data/{SAMPLENAME}_2.fastq'
SAMPLENAMES, = glob_wildcards(R1)

# path to results folder and textfile outputs
RESULT_PATH = PROJECT_PATH + '/results/{SAMPLENAME}'
TRIMMED_FQ = RESULT_PATH + '/trimmed.fq.gz'
MERGED_FQ = RESULT_PATH + '/merged.fq.gz'
BAM = RESULT_PATH + '/aligned.bam'
TRIMMED_BAM = RESULT_PATH + '/trimmed.bam'
SORTED_BAM = RESULT_PATH + '/sorted.bam'
DEPTH_FILE = RESULT_PATH + '/coverage.per-base.bed.gz'
SNP_FILE = RESULT_PATH + '/variants.snp'
COVERAGE_STAT = PROJECT_PATH + '/results/coverage_stat.csv'
FREQ_FILE = RESULT_PATH + '/MBCS_freq.tsv'

# paths to all figure outputs of this script
SEQ_LOGO = RESULT_PATH + '/MBCS_seqlogo.png'
COVERAGE_PNG_PER_SAMPLE = RESULT_PATH + '/coverage.pdf'
COVERAGE_PNG = PROJECT_PATH + '/results/coverage.png'
rule all:
    input:
        expand(SNP_FILE, SAMPLENAME = SAMPLENAMES),
        expand(SEQ_LOGO, SAMPLENAME = SAMPLENAMES),
        expand(FREQ_FILE, SAMPLENAME = SAMPLENAMES),
        expand(COVERAGE_PNG_PER_SAMPLE, SAMPLENAME = SAMPLENAMES),
        COVERAGE_PNG, COVERAGE_STAT

rule plotDepth_per_sample:
    input:
        DEPTH_FILE
    
    params:
        CODE_PATH = CODE_PATH
    output:
        COVERAGE_PNG_PER_SAMPLE
    
    shell:
        'python {params.CODE_PATH}/coverage_plot.py {input} {output}'

rule plotDepth:
    input:
        expand(DEPTH_FILE, SAMPLENAME = SAMPLENAMES)

    output:
       FIG =  COVERAGE_PNG,
       TAB = COVERAGE_STAT

    run:
        def read_bed(bed):
            return pd.read_csv(bed, names = ['chrom','start','end','read_coverage'], sep='\t') \
                .assign(samplename = os.path.basename(os.path.dirname(bed))) \
                .assign(log_cov = lambda d: d.read_coverage.transform(np.log))
        
        
        dfs = map(read_bed, input)
        df = pd.concat(dfs)
        
        #make table
        df\
            .groupby('samplename', as_index=False)\
            .agg({'read_coverage':'median'})\
            .rename(columns = {'read_coverage':'median read coverage'})\
            .merge(df\
                    .groupby('samplename', as_index=False)\
                    .agg({'read_coverage':'mean'})\
                    .rename(columns = {'read_coverage':'mean read coverage'}))\
            .to_csv(output.TAB, index=False)
    
        #make figure
        p = sns.FacetGrid(data = df, col_wrap = 5, col = 'samplename')
        p.map(plt.plot, 'end', 'log_cov')
        p.set_titles(col_template = '{col_name}')
        sns.despine()
        p.set(xlabel = 'Read coverage (log)', ylabel = 'Genomic position')
        p.savefig(output.FIG, bbox_inches='tight')




rule cal_depth:
    input:
        SORTED_BAM

    params:
        PREFIX = RESULT_PATH + '/coverage'

    output:
        DEPTH_FILE 
    
    shell:
        'mosdepth {params.PREFIX} {input}'
        

rule cal_frequency:
    input:
        SORTED_BAM

    params:
        CODE_PATH = CODE_PATH
    output:
        SEQ_LOGO = SEQ_LOGO, 
        FREQ_FILE = FREQ_FILE

    shell:
        'python {params.CODE_PATH}/extract_MBCS.py {input} {output.FREQ_FILE} {output.SEQ_LOGO}'


rule variant_calling_with_varscan:
    input:
        SORTED_BAM

    params:
        REF_FA = REF

    output:
        SNP_FILE
    
    shell:
        'samtools mpileup --excl-flags 2048 --excl-flags 256  '\
        '--fasta-ref {params.REF_FA} '\
        '--max-depth 50000 --min-MQ 30 --min-BQ 30  {input} '\
        '| varscan pileup2cns '\
        ' --min-coverage 10 ' \
        ' --min-reads2 2 '\
        '--min-var-freq 0.01 '\
        '--min-freq-for-hom 0.75 '
        '--p-value 0.05 --variants 1 ' \
        '> {output}'

rule sort_bam_with_samtools:
    input:
        TRIMMED_BAM

    output:
        SORTED_BAM
    
    shell:
        'samtools sort {input} > {output};'\
        ' samtools index {output}'

#removed invalid option -Q
rule trim_primers_from_alignment_with_bamutils:
    input:
        BAM

    params:
        REF_FA = REF,
        PRIMERS = PRIMERS

    output:
        TRIMMED_BAM

    shell:
        'bam trimbam {input} - -L 30 -R 0 --clip '\
        '| samtools fixmate - - '\
        '| samtools calmd - {params.REF_FA} '\
        '> {output} '


rule align_with_bowtie:
    input:
        TRIMMED_FQ

    params:
        REF = REF

    output:
        BAM

    shell:
        'bowtie2 -x {params.REF} '\
        '--no-discordant --dovetail --no-mixed --maxins 2000 ' \
        '--interleaved {input} --mm '\
        '| samtools view -bF 4  > {output}'

rule trim_adapter_with_cutadapt:
    input:
        FQ1 = R1,
        FQ2 = R2
        
    output:
        TRIMMED_FQ

    shell:
        'seqtk mergepe {input.FQ1} {input.FQ2} '\
        '| cutadapt -B AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTG '\
        '-b AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC '\
        '--interleaved --minimum-length 50 '\
        '-o {output} -'
