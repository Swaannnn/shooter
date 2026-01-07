FROM ubuntu:22.04

# Install Godot dependencies (Headless)
RUN apt-get update && apt-get install -y \
	wget \
	unzip \
	libfontconfig1 \
	mesa-utils \
	libgl1-mesa-glx \
	libxcursor1 \
	libxinerama1 \
	libxrandr2 \
    libxrender1 \
    libxi6 \
    alsa-utils \
    pulseaudio \
	&& rm -rf /var/lib/apt/lists/*

# Download Godot Server (Headless)
ENV GODOT_VERSION "4.5.1"
RUN wget https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && unzip Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip \
    && mv Godot_v${GODOT_VERSION}-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip

# Create app directory
WORKDIR /app

# Copy the PCK/Executable from the build context (We will build this in CI or user must provide)
# For simplicity, we assume we export the .pck and .x86_64 to a folder named 'server'
# But wait, Godot release on Github doesn't include the User's game. 
# We need to copy the project files and Import? No, better to Export Linux build and copy it.

# Let's assume we copy the ENTIRE project and run it with editor (slow) OR copy exported files.
# Render creates image from Repo. So we have source code.
# We can run Godot Editor in Headless mode to export OR run from source (slower start but easier setup).
# Running from source in 4.x headless is viable.

COPY . .

# Import assets once (to generate .godot folder)
RUN godot --headless --editor --quit --verbose

# Expose Port
EXPOSE 7777

# Run Game Server
# --headless: No graphics
# --server: Custom flag we will add to NetworkManager to Auto-Host
CMD ["godot", "--headless", "--server"]
