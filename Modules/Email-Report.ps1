function Convert-FileToGraphAttachment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $name = Split-Path -Path $Path -Leaf

    return @{
        "@odata.type" = "#microsoft.graph.fileAttachment"
        name = $name
        contentType = if ($name -like "*.pdf") { "application/pdf" } else { "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
        contentBytes = [Convert]::ToBase64String($bytes)
    }
}

function Get-RecipientEmailsFromGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupEmail,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    $escapedGroupEmail = $GroupEmail.Replace("'", "''")
    $groupFilter = [System.Uri]::EscapeDataString("mail eq '$escapedGroupEmail'")
    $groupLookupUri = "https://graph.microsoft.com/v1.0/groups?`$filter=$groupFilter&`$select=id,mail,displayName"
    $groupLookup = Invoke-GraphWithRetry -Method GET -Uri $groupLookupUri -GraphConfig $GraphConfig

    if (-not $groupLookup.value -or $groupLookup.value.Count -eq 0) {
        return @()
    }

    $groupId = $groupLookup.value[0].id
    if (-not $groupId) {
        return @()
    }

    $membersUri = "https://graph.microsoft.com/v1.0/groups/$groupId/members/microsoft.graph.user?`$select=mail,userPrincipalName,accountEnabled"
    $members = Invoke-GraphPaged -Uri $membersUri -GraphConfig $GraphConfig
    if (-not $members) {
        return @()
    }

    $resolved = @()
    foreach ($member in $members) {
        if (($member.PSObject.Properties.Name -contains "accountEnabled") -and -not $member.accountEnabled) {
            continue
        }

        if ($member.mail) {
            $resolved += [string]$member.mail
            continue
        }

        if ($member.userPrincipalName) {
            $resolved += [string]$member.userPrincipalName
        }
    }

    return @($resolved | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Resolve-RecipientEmails {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Recipients,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    $expanded = @()

    foreach ($recipient in $Recipients) {
        $groupMembers = @()
        try {
            $groupMembers = Get-RecipientEmailsFromGroup -GroupEmail $recipient -GraphConfig $GraphConfig
        }
        catch {
            # If group expansion fails, fall back to original recipient address.
            $groupMembers = @()
        }

        if ($groupMembers.Count -gt 0) {
            $expanded += $groupMembers
        }
        else {
            $expanded += $recipient
        }
    }

    return @($expanded | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Send-ReportEmail {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$EmailConfig,

        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$BodyHtml,

        [Parameter(Mandatory = $true)]
        [string[]]$AttachmentPaths,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    $resolvedRecipients = Resolve-RecipientEmails -Recipients @($EmailConfig.ToRecipients) -GraphConfig $GraphConfig

    $toRecipients = @()
    foreach ($email in $resolvedRecipients) {
        $toRecipients += @{
            emailAddress = @{
                address = $email
            }
        }
    }

    $attachments = @()
    foreach ($path in $AttachmentPaths) {
        if (Test-Path -LiteralPath $path) {
            $attachments += Convert-FileToGraphAttachment -Path $path
        }
    }

    $payload = @{
        message = @{
            subject = $Subject
            body = @{
                contentType = "HTML"
                content = $BodyHtml
            }
            toRecipients = $toRecipients
            attachments = $attachments
        }
        saveToSentItems = $true
    }

    $sendUri = "https://graph.microsoft.com/v1.0/users/$($EmailConfig.SenderMailbox)/sendMail"
    Invoke-GraphWithRetry -Method POST -Uri $sendUri -Body $payload -GraphConfig $GraphConfig | Out-Null
}
