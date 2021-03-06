#!/usr/bin/env bash

: '
Upload a folder from ica using the aws s3 sync command
Parameters captured outside of --gds-path are used as upload parameters
'

ica_aws_s3_folder_upload() {
  : '
  Takes in one input in the while loop (which is --gds-path).
  Maintains all other parameters as part of the aws s3 sync command
  You will need the following binaries:
  * python3
  * aws
  * jq
  '

  # Help function
  _print_help(){
    echo "
          Usage: ica_aws_s3_folder_upload --gds-path gds://volume-name/path-to-folder/ --src-path downloads/

          Options:
              -g / --gds-path: Path to gds file
              -b / --base-url: ICA base url, https://aps2.platform.illumina.com by default
              -s / --src-path: The path you'd like to src the data to. Working dir by default.

          Requirements:
            * aws
            * jq     (v1.5+)
            * python3 (v3.4+)

          You will need to set the ICA_ACCESS_TOKEN environment variable to run this program.

          Extras:
          You can also use any of the aws s3 sync parameters to add to the command list, for example
          ica_aws_s3_files_upload --gds-path gds://volume-name/path-to-folder/ --exclude='*' --include='*.fastq.gz'
          will upload only fastq files from that folder.

          If you are unsure on what files will be uploaded, use the --dryrun parameter. This will inform you of which
          files will be uploaded from your local file system.

          Unlike rsync, trailing slashes on the --gds-path and --src-path do not matter. One can assume that
          a trailing slash exists on both parameters. This means that the contents inside the --src-path parameter are
          placed inside the --gds-path parameter. 
          "
  }

  ## Internal functions
  _echo_stderr(){
    echo "$@" 1>&2
  }

  _binaries_check(){
    : '
    Check each of the required binaries are available
    '
    if ! (type aws jq python3 1>/dev/null); then
      return 1
    fi
  }

  # Check destination path
  _check_src_path(){
    local src_path="$1"

    if [[ ! -d "${src_path}" ]]; then
      _echo_stderr "Error could not find \"${src_path}\". --src path must exist as a file or folder"
    fi
  }

  # Get volume from gds path
  _get_volume_from_gds_path() {
    : '
    Assumes urllib is available on python3
    '
    local gds_path="$1"

    # Returns the netloc attribute of the gds_path
    python3 -c "from urllib.parse import urlparse; print(urlparse(\"${gds_path}\").netloc)"
  }

  # Get folder path
  _get_folder_path_from_gds_path() {
    : '
    Assumes urllib is available on python3
    '
    local gds_path="$1"

    # Returns the path attribute of gds_path input
    python3 -c "from urllib.parse import urlparse; print(urlparse(\"${gds_path}\").path)"
  }

  # Get folder id
  _get_folder_id() {
    : '
    Use folders list on the folder and collect the folder id from the single item
    '
    local volume_name="$1"
    local folder_path="$2"
    local access_token="$3"
    local base_url="$4"

    # Pipe curl output into jq to collect ID and return
    curl \
      --silent \
      --request GET \
      --header "Authorization: Bearer ${access_token}" \
      "${base_url}/v1/folders?volume.name=${volume_name}&path=${folder_path}" |
      jq \
        --raw-output \
        '.items[] | .id'
  }

  # Get aws access creds from folder id
  _get_aws_access_creds_from_folder_id() {
    : '
    Use folders list on the folder and collect the folder id from the single item
    '
    local folder_id="$1"
    local access_token="$2"
    local base_url="$3"

    # https://ica-docs.readme.io/reference#updatefolder expects
    # --header 'Content-Type: application/*+json'
    # We're not actually patching anything, we're just getting some temporary credss
    curl \
      --silent \
      --request PATCH \
      --header 'Accept: application/json' \
      --header 'Content-Type: application/*+json' \
      --header "Authorization: Bearer ${access_token}" \
      "${base_url}/v1/folders/${folder_id}?include=objectStoreAccess" | {
      # We take the S3 upload creds
      # Even though we're downloading only, aws s3 sync needs the put request param
      jq \
        --raw-output \
        '.objectStoreAccess.awsS3TemporaryUploadCredentials'
    }

  }

  # Credential get functions
  _get_access_key_id_from_credentials() {
    : '
    Returns access_Key_id attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.access_Key_Id'
  }

  _get_secret_access_key_from_credentials() {
    : '
    Returns secret_Access_Key attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.secret_Access_Key'
  }

  _get_session_token_from_credentials() {
    : '
    Returns the session_Token attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.session_Token'
  }

  _get_region_from_credentials() {
    : '
    Returns the region attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.region'

  }

  _get_bucket_name_from_credentials() {
    : '
    Returns the bucketName attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.bucketName'

  }

  _get_folder_parent_from_folder_path() {
    : '
    Returns the gds folder parent name from the folder path
    '
    local gds_folder_path="$1"

    python3 -c "from pathlib import Path; print(Path(\"${gds_folder_path}\").parent)"
  }

  _get_folder_name_from_folder_path() {
    : '
    Returns the gds folder name from the folder path
    '

    local gds_folder_path="$1"

    python3 -c "from pathlib import Path; print(Path(\"${gds_folder_path}\").name)"

  }

  _get_key_prefix_from_credentials() {
    : '
    Returns the keyPrefix attribute
    '

    local aws_credentials="$1"

    echo "${aws_credentials}" | jq --raw-output '.keyPrefix'

  }

  _create_gds_folder() {
  : '
  Create a gds folder and get temporary access credentials too
  '

  local volume_name="$1"
  local folder_parent="$2"
  local folder_name="$3"
  local access_token="$4"
  local base_url="$5"

  # Create a json object as the --data-raw attribute
  body_arg="$(jq --raw-output \
                 --arg "volumeName" "${volume_name}" \
                 --arg "folderPath" "${folder_parent}/" \
                 --arg "name" "${folder_name}" \
                 '. | .["volumeName"]=$volumeName | .["folderPath"]=$folderPath | .["name"]=$name' <<< '{}'
            )"

  # Pipe curl output into jq to collect ID and return
  curl \
    --silent \
    --request POST \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer ${access_token}" \
    --data-raw "${body_arg}" \
    "${base_url}/v1/folders" |
    jq \
      --raw-output \
      '.id'
  }

  _strip_path_from_base_url() {
    : '
    Base url should not contain any path content. We use python3 urlparse to return just the scheme and netloc.
    '
    local base_url="$1"

    # Returns the path attribute of base_url input
    python3 -c "from urllib.parse import urlparse; print(urlparse(\"${base_url}\").scheme + \"://\" + urlparse(\"${base_url}\").netloc)"
  }

  # Start main

  # Set local vars
  local aws_s3_sync_args=()
  local gds_path=""
  local src_path="$PWD"
  local base_url="https://aps2.platform.illumina.com"
  local access_token="${ICA_ACCESS_TOKEN}"

  # Check available binaries exist
  if ! _binaries_check; then
    _echo_stderr "Please make sure binaries aws, jq and python3 are all available on your PATH variable"
    _print_help
    return 1
  fi

  # Get args from command line
  while [ $# -gt 0 ]; do
    case "$1" in
      -g | --gds-path)
        gds_path="$2"
        shift 1
        ;;
      -b | --base-url)
        base_url="$2"
        shift 1
        ;;
      -s | --src-path)
        src_path="$2"
        shift 1
        ;;
      -h | --help)
        _print_help
        return 0
        ;;
      --*)
        # Let's add in the parameter arg
        aws_s3_sync_args=("${aws_s3_sync_args[@]}" "$1")
        # First check if $2 is of any length
        if [[ -n "$2" ]]; then
          # Check if the parameter takes a value
          case "$2" in
            --*)
              # Check if just another parameter, ignore for now
              :
              ;;
            *)
              aws_s3_sync_args=("${aws_s3_sync_args[@]}" "$2")
              shift 1
              ;;
          esac
        fi
        ;;
    esac
    shift 1
  done

  # Check mandatory args are defined
  if [[ -z "${gds_path}" ]]; then
    _echo_stderr "Please set --gds-path"
    return 1
  elif [[ -z "${access_token}" ]]; then
    _echo_stderr "Please set the env var ICA_ACCESS_TOKEN"
    return 1
  fi
  _check_src_path "${src_path}"

  # Strip base url
  base_url="$(_strip_path_from_base_url "${base_url}")"

  # Now run the aws s3 sync command through eval to quote the necessary arguments
  # Split volume and path
  gds_volume="$(_get_volume_from_gds_path "${gds_path}")"
  gds_folder_path="$(_get_folder_path_from_gds_path "${gds_path}")"

  # Check gds_folder_path
  # This script is not supported where the gds_folder_path is just '/'
  if [[ "${gds_folder_path}" == "/" ]]; then
    _echo_stderr "Sync to root volume \"${gds_path}\" is not supported. Please specify a subfolder of this folder to sync to"
    return 1
  fi

  # Split path into name and parent
  gds_folder_parent="$(_get_folder_parent_from_folder_path "${gds_folder_path}")"
  gds_folder_name="$(_get_folder_name_from_folder_path "${gds_folder_path}")"

  # Get the folder id
  folder_id="$(_get_folder_id "${gds_volume}" "${gds_folder_path}" "${access_token}" "${base_url}")"

  # Check folder exists
  if [[ -z "${folder_id}" ]]; then
    _echo_stderr "Creating the gds folder \"${gds_path}\""
    folder_id="$(_create_gds_folder "${gds_volume}" "${gds_folder_parent}" "${gds_folder_name}" "${access_token}" "${base_url}")"

    # Now re-check folder was created successfully
    if [[ -z "${folder_id}"  ]]; then
      _echo_stderr "Creation of folder \"gds://${gds_volume}${gds_folder_path}\" failed"
      return 1
    fi
  fi

  # Get the json aws creds with the curl PATCH command
  aws_credentials="$(_get_aws_access_creds_from_folder_id "${folder_id}" "${access_token}" "${base_url}")"

  # Creds to be exported
  aws_access_key_id="$(_get_access_key_id_from_credentials "${aws_credentials}")"
  aws_secret_access_key="$(_get_secret_access_key_from_credentials "${aws_credentials}")"
  aws_session_token="$(_get_session_token_from_credentials "${aws_credentials}")"
  aws_default_region="$(_get_region_from_credentials "${aws_credentials}")"

  # Components of positional parameter 1
  aws_bucket_name="$(_get_bucket_name_from_credentials "${aws_credentials}")"
  aws_key_prefix="$(_get_key_prefix_from_credentials "${aws_credentials}")"

  # Check at least one of the important ones is defined
  if [[ -z "${aws_access_key_id}" || "${aws_access_key_id}" == "null" ]]; then
    _echo_stderr "Could not get aws access key id, are you sure you have write permissions to the folder \"${gds_path}\"?"
    return 1
  fi

  # Run command through eval and set env vars
  (
    # Export env vars in subshell
    export AWS_ACCESS_KEY_ID="${aws_access_key_id}"
    export AWS_SECRET_ACCESS_KEY="${aws_secret_access_key}"
    export AWS_SESSION_TOKEN="${aws_session_token}"
    export AWS_DEFAULT_REGION="${aws_default_region}"
    eval aws s3 sync "${src_path}" "s3://${aws_bucket_name}/${aws_key_prefix}" '"${aws_s3_sync_args[@]}"'
  )

}
