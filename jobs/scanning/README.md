The purpose of this job is to:
1. Run coverity scans against a codebase
2. Store the results of that scan on the buildvm NFS
3. If a previous commit of the scanned codebase has already been scanned, compute the difference between the most recent commit and the new scan.
4. If the new scan results in anything that has not been waived during a previous commit's scan, notify artists.
5. The artist should work with engineering to justify fixing the coverity reported items or to justify why the reported items are not important to fix.
6. If the problems are going to be fixed, the pipeline should be canceled. 
7. If the problems are to be waived, the pipeline should be allowed to continue. The slack thread & approving engineer should be recorded in the pipeline.
8. If the differences are waived, the scan results for the commit will be copied to the nfs share as having been waived. 
9. The next commit to be scanned will ignore issues waived in the previous commit's scan.

How the job works:
The refresh-scanner-images job must be run periodically to create an golang builder image, appropriate for a given release,
which also has the coverity tools installed within it. A scanner image should be created for each release (since the 
golang compiler may be different for each release).

Once scanner images are created, they can be used to build codebases with coverity monitoring the build and emitting 
information about those builds. The build is performed within a container created from a scanner image. The result
of the build is shared with the buildvm by virtual a mounted volume ("./cov" in the Jenkins workspace). Once the build
completes successfully, the results must be analyzed with cov-analyze. cov-analyze is launched on the buildvm host
(since it is not really important to run it in a container). The analysis step is time consuming for large codebases.
The results of the analysis are also captured in the ./cov directory.

The analysis is then converted int a json format and an html format (raw_results.*). The pipeline will then attempt to compute a diff
between the new results and any previously waived results for the codebase. In the case of a git repo, it will iterate through 
previous commit ids and check for waived results in `/mnt/nfs/coverity/waived/${PREVIOUS_SHA}` . If it finds previously waived
results, it will subtract them from the raw result using csdiff and created: diff_results.js and diff_results.html. If no previous
commit was found, diff_results == raw_results. Once a diff has been computed, the results js/html will be copied `/mnt/nfs/coverity/scans/${SHA}`.  
If a scan is triggered for the same SHA, it will be skipped if this directory already exists (unless RE_SCAN is set to true).


Before concluding the scan portion of the pipeline, the diff_results and raw_results will be copied out to rcm-guest. This is to allow engineering resources an 
easy location to look through coverity results.

This ends the scanning stage. If diff_results contains any items (i.e. issues created since the last waiver), the pipeline
will prompt for user input. An artist must provide details about why a waiver is permitted in order to continue. Information about
the waiver will be recorded on the NFS (including which artist made the approval). If the pipeline is aborted, the scan results will
be retained, but they will not be considered waived.

If results are waived, a symlink will be made from `/mnt/nfs/coverity/waived/${SHA}` to `/mnt/nfs/coverity/scans/${SHA}`. The existence
of this link allows subsequenct runs of the pipelines on the same repository to pare down results to only new, unwaived, issues.
