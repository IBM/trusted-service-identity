#!/bin/bash +x

SECRET_NAME="SECRET_NAME"
SECRET_VALUE='SECRET_VALUE'

## create help menu:
helpme()
{
  cat <<HELPMEHELPME
This script helps building TSI policies

syntax:
   $0 [pod-to-inspect] [namespace] [policy-type]

where:
      [pod-to-inspect]
      [namespace]: namespace of the application container

HELPMEHELPME
}

# {
#   "cluster-name": "my-cluster-name",
#   "region": "eu-de",
#   "exp": 1590494405,
#   "iat": 1590494345,
#   "images": "30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc",
#   "images-names": "ubuntu@sha256:250cc6f3f3ffc5cdaa9d8f4946ac79821aafb4d3afc93928f0de9336eba21aa4",
#   "iss": "wsched@us.ibm.com",
#   "machineid": "b46e165c32d342d9896d9eeb43c4d5dd",
#   "namespace": "test",
#   "pod": "myubuntu-6756d665bc-cb49l",
#   "sub": "wsched@us.ibm.com"
# }
# root@myubuntu-6756d665bc-cb49l:/# cat jwt/token | cut -d"." -f2 |base64 --decode |jq -r '.images'
# 30beed0665d9cb4df616cca84ef2c06d2323e02869fcca8bbfbf0d8c5a3987cc

# validate the arguments
if [[ "$1" == "-?" || "$1" == "-h" || "$1" == "--help" || "$2" == "" ]] ; then
    helpme
else
  POD="$1"
  NS="$2"
fi


if [[ "$3" == "" ]] ; then

# options=("1 (Region)" "2 (Region+Img)" "3 (Region+Cluster+Img)" "Quit")
# select opt in "${options[@]}"
#
# do
#     case $opt in
#         "1")
#             echo "you chose choice 1"
#             ;;
#         "2")
#             echo "you chose choice 2"
#             ;;
#         "3")
#             echo "you chose choice $REPLY which is $opt"
#             ;;
#         "Quit")
#             break
#             ;;
#         *) echo "invalid option $REPLY";;
#     esac
# done

PS3='What policy to use?: '
options=("Region" "Region+Img" "Region+Cluster+Img" "Region+Cluster+Namespace+Img" "Custom" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Region")
            echo "you chose $REPLY which is $opt"
            POLICY="R"
            break
            ;;
        "Region+Img")
            echo "you chose $REPLY which is $opt"
            POLICY="RI"
            break
            ;;
        "Region+Cluster+Img")
            echo "you chose $REPLY which is $opt"
            POLICY="RCI"
            break
            ;;
        "Region+Cluster+Namespace+Img")
            echo "you chose $REPLY which is $opt"
            POLICY="RCNI"
            break
            ;;
        "Custom")
            echo "you chose $REPLY which is $opt"
            POLICY="C"
            break
            ;;
        "Quit")
            exit
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
else
  POLICY="$3"
fi

CLAIMS=$(kubectl -n "$NS" exec -it "$POD" -c jwt-sidecar -- sh -c 'cat jwt/token | cut -d"." -f2 |base64 --decode' | jq)
#echo "$CLAIMS"

case $POLICY in
    "R")
        echo "policy $POLICY"
        PL="tsi-r"
        REGION=`echo $CLAIMS |jq -r '."region"'`
        echo "vault kv put secret/${PL}/${REGION}/${SECRET_NAME} ${SECRET_VALUE}"
        ;;
    "RI")
        echo "policy $POLICY"
        PL="tsi-ri"
        REGION=`echo $CLAIMS |jq -r '."region"'`
        IMG=`echo $CLAIMS |jq -r '."images"'`
        echo "vault kv put secret/${PL}/${REGION}/${IMG}/${SECRET_NAME} ${SECRET_VALUE}"
        ;;

    "RCI")
        echo "policy $POLICY"
        PL="tsi-r"
        REGION=`echo $CLAIMS |jq -r '."region"'`
        CLUSTER=`echo $CLAIMS |jq -r '."cluster-name"'`
        IMG=`echo $CLAIMS |jq -r '."images"'`
        echo "vault kv put secret/${PL}/${REGION}/${CLUSTER}/${IMG}/${SECRET_NAME} ${SECRET_VALUE}"
        ;;
    "RCNI")
        echo "policy $POLICY"
        PL="tsi-rcni"
        REGION=`echo $CLAIMS |jq -r '."region"'`
        CLUSTER=`echo $CLAIMS |jq -r '."cluster-name"'`
        NS=`echo $CLAIMS |jq -r '."namespace"'`
        IMG=`echo $CLAIMS |jq -r '."images"'`
        echo "vault kv put secret/${PL}/${REGION}/${CLUSTER}/${NS}/${IMG}/${SECRET_NAME} ${SECRET_VALUE}"
        ;;
    "C")
       echo "Use claims to build custom policy"
       echo "$CLAIMS"
       echo "Format:"
       echo 'vault kv put secret/{policy-name}/{claim1-value}/{claim2-value}/(...)/'"${SECRET_NAME} ${SECRET_VALUE}"
        ;;
    "Quit")
        exit
        ;;
    *) echo "invalid option $POLICY";;
esac
