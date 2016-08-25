#!/bin/bash
set -ex

# ------------------------------------
# Step 1: Determine target color
# ------------------------------------
ORIGINAL_COLOR=$(curl -s -XGET -H "Authorization: Bearer ${API_TOKEN}" ${SERVICE_MANAGER}/api/kv/blue-green/${APP_NAME}/current?raw=true)
TARGET_COLOR=$(echo "bluegreen" | sed -e s/${ORIGINAL_COLOR}//)

# ------------------------------------
# Step 2: Trigger deploy via API
# ------------------------------------
POSTDATA=$(cat <<ENDOFTEMPLATE
{
  "deployment_id": "${APP_NAME}-${TARGET_COLOR}",
  "deployment_name": "${APP_FRIENDLY_NAME} ${TRAVIS_BUILD_NUMBER}",
  "desired_state": 1,
  "placement": {
    "pool_id": "default"
  },
  "quantities": {
    "helloworld": 3
  },
  "stack": {
    "content": "version: 2\nservices:\n  app:\n    image: \"${DOCKER_REGISTRY}/${DOCKER_IMAGE}:${TRAVIS_BUILD_NUMBER}\"\n    ports:\n      - ${EXPOSED_PORT}/tcp\n    environment:\n      - \"occs:availability=per-pool\"\n      - \"occs:scheduler=random\"\n",
    "service_id": "app",
    "service_name": "${APP_FRIENDLY_NAME} ${TRAVIS_BUILD_NUMBER}",
    "subtype": "service"
  }
}
ENDOFTEMPLATE
)

curl -XPOST -H "Authorization: Bearer ${API_TOKEN}" -d "${POSTDATA}" ${SERVICE_MANAGER}/api/v2/deployments/

# ------------------------------------
# Step 3: Store service discovery key for target color
# ------------------------------------
curl -s -XPUT -H "Authorization: Bearer ${API_TOKEN}" -d "apps/app-${APP_NAME}-${TARGET_COLOR}-${EXPOSED_PORT}/containers" ${SERVICE_MANAGER}/api/kv/blue-green/${APP_NAME}/${TARGET_COLOR}/id

# ------------------------------------
# Step 4: Wait for the target color to come online
# ------------------------------------
TRY=0
MAX_TRIES=12
WAIT_SECONDS=5
HEALTHY=0
while [ $TRY -lt $MAX_TRIES ]; do
 TRY=$(( $TRY + 1 ))
 RESPONSE=$(curl -s -XGET -H "Authorization: Bearer ${API_TOKEN}" ${SERVICE_MANAGER}/api/v2/deployments/${APP_NAME}-${TARGET_COLOR} | jq ".deployment | .current_state == .desired_state")

 if [ "RESPONSE" == "true" ]; then
  HEALTHY=1
  break
 fi
 echo "Current and desired state of deployment do not match. ${TRY} of ${MAX_TRIES} tries."
 sleep $WAIT_SECONDS
done

if [ $HEALTHY -gt 0 ]; then
  echo "Current and desired state of deployment match. Continuing."
else
  echo "Tried ${MAX_TRIES} times but deployment is not healthy."
  exit 1
fi

# ------------------------------------
# Step 5: Point load balancer at new services
# ------------------------------------
curl -s -XPUT -H "Authorization: Bearer ${API_TOKEN}" -d "${TARGET_COLOR}" ${SERVICE_MANAGER}/api/kv/blue-green/${APP_NAME}/current

# ------------------------------------
# Step 6: Remove original deployment
# ------------------------------------
# First, the deployment must be stopped
curl -s -XPOST -H "Authorization: Bearer ${API_TOKEN}" ${SERVICE_MANAGER}/api/v2/deployments/${APP_NAME}-${ORIGINAL_COLOR}/stop

# Make sure it has stopped
TRY=0
MAX_TRIES=12
WAIT_SECONDS=5
STOPPED=0
while [ $TRY -lt $MAX_TRIES ]; do
 TRY=$(( $TRY + 1 ))
 RESPONSE=$(curl -s -XGET -H "Authorization: Bearer ${API_TOKEN}" ${SERVICE_MANAGER}/api/v2/deployments/${APP_NAME}-${TARGET_COLOR} | jq ".deployment | .current_state == .desired_state")

 if [ "RESPONSE" == "true" ]; then
  STOPPED=1
  break
 fi
 echo "Current and desired state of deployment do not match. ${TRY} of ${MAX_TRIES} tries."
 sleep $WAIT_SECONDS
done

if [ $STOPPED -gt 0 ]; then
  # Finally, remove the deployment, and reset the ID
  echo "Original deployment has stopped. Removing the deployment for ${APP_NAME}-${ORIGINAL_COLOR}."
  curl -s -XDELETE -H "Authorization: Bearer ${API_TOKEN}" ${SERVICE_MANAGER}/api/v2/deployments/${APP_NAME}-${ORIGINAL_COLOR}
  curl -s -XPUT -H "Authorization: Bearer ${API_TOKEN}" -d "blue-green/null" ${SERVICE_MANAGER}/api/kv/blue-green/${APP_NAME}/${ORIGINAL_COLOR}/id
else
  echo "Checked ${MAX_TRIES} times but deployment is not stopped. You may need to stop it manually."
fi

# ------------------------------------
# We made it to the end. All is well!
# ------------------------------------
exit 0
