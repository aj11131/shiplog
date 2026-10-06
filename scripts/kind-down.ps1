<#
.SYNOPSIS
  Deletes the local "shiplog" kind cluster and everything in it (including the database volume).
#>
$ErrorActionPreference = 'Stop'
kind delete cluster --name shiplog
