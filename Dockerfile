# Use a lightweight Nginx image
FROM nginx:alpine

# Copy the HTML file to the default Nginx public directory
# We rename it to index.html so it loads automatically at the root URL
COPY leadvyne-onboarding.html /usr/share/nginx/html/index.html

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
