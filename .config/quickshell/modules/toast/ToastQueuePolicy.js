.pragma library

function sortQueue(queue) {
    return queue.slice().sort((a, b) => {
        const dp = b.priority - a.priority;
        if (dp !== 0)
            return dp;
        return a.serial - b.serial;
    });
}

function findQueuedOsd(queue, kind) {
    for (let i = 0; i < queue.length; i++) {
        const activity = queue[i];
        if (activity?.data?.activityType === "osd" && activity.data?.kind === kind)
            return activity;
    }
    return null;
}

function decidePush(currentActivity, finishingActivityId, newActivity) {
    const isNotif = newActivity.data?.activityType === "notification";
    const curIsNotif = currentActivity?.data?.activityType === "notification";

    if (curIsNotif && isNotif)
        return { action: "queue" };
    if (currentActivity === null)
        return { action: "present", bumpCurrent: false };
    if (finishingActivityId)
        return { action: "queue" };
    if (newActivity.priority > currentActivity.priority)
        return { action: "present", bumpCurrent: true };
    return { action: "extend" };
}
