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

    $toRecipients = @()
    foreach ($email in $EmailConfig.ToRecipients) {
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
