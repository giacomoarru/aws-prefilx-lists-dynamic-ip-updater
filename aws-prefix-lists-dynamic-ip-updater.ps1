# This script updates managed prefix lists with your dynamic IP to allow access from DEV ENV to AWS resources
# It only supports 1 IP but it is easily modifiable to support multiple if needed
# by Jack Arru - x2x cloud

# Your AWS profile
$aws_profile = "PROFILE"

# config map
# region/pl id
$mpl_map = @{"eu-west-1" = "pl-id1"; "eu-south-1" = "pl-id2"}

# to get current ip address in cidr format
$my_ip = (Invoke-RestMethod http://ipinfo.io/json).ip
$pattern = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
if ($my_ip -notmatch $pattern) {
    Write-Error Cannot get external IP Address
    Exit 1
}

$my_ip = $my_ip +"/32"

foreach ($region in $mpl_map.Keys) {
    $pl = (aws ec2 describe-managed-prefix-lists --profile $aws_profile --region $region --prefix-list-ids $mpl_map[$region] --no-paginate) | ConvertFrom-Json
    $version = $pl.PrefixLists[0].Version
    Write-Host Processing version $version of $mpl_map[$region] in $region
    $entries = (aws ec2 get-managed-prefix-list-entries --profile $aws_profile --region $region --prefix-list-id $mpl_map[$region] --no-paginate) | ConvertFrom-Json
    $skip = $False
    foreach ($entry in $entries.Entries) {
        if ($entry.Cidr -eq $my_ip) {
            Write-Host IP already present: $entry.Cidr in $region - skipping
            $skip = $True
            continue
        }
        Write-Host Removing outdated ip $entry.Cidr in $region
        $result = (aws --profile $aws_profile --region $region ec2 modify-managed-prefix-list --prefix-list-id $mpl_map[$region] --remove-entries Cidr=$($entry.Cidr) --current-version $version)
        if ($LASTEXITCODE -eq 0) {
            $version++
            Write-Host "Success"
        } else {
            Write-Host "Command failed"
        }
    }
    if (-not($skip)) {
        Write-Host Adding current ip $my_ip in $region
        $result = (aws --profile $aws_profile --region $region ec2 modify-managed-prefix-list --prefix-list-id $mpl_map[$region] --add-entries Cidr=$my_ip,Description=home-swords --current-version $version)
        if ($LASTEXITCODE -eq 0) {
            $version++
            Write-Host "Success"
        } else {
            Write-Host "Command failed"
        }
    }
}

