#!/usr/bin/python3
import glob

def main():
	snp_files = glob.glob("../results/*/*.snp")
	out_filename = "../results/all_variants.snp"
	print ("writing %s" % out_filename)
	outfile = open(out_filename,'w')
	header = 1
	for snp_file in snp_files):
		sampleID = snp_file.rsplit('/')[2]
		infile = open(snp_file,'r')
		for line in infile.readlines():
			if "Chrom" in line and header == 1:
				outfile.write("Sample"+"\t"+line)
				header = 0
			elif "Chrom" in line and header == 0:
				continue
			else:
				outfile.write(sampleID+"\t"+line)
		infile.close()

if __name__ == "__main__":
	main()
